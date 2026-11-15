module MolliePay
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    include MolliePay::HasUuid

    # Mollie sends amounts as { currency:, value: "10.00" } (a decimal string).
    # Parse straight to exact BigDecimal; never through cents or Float.
    def self.mollie_value_to_decimal(mollie_amount)
      BigDecimal(mollie_amount.value)
    end

    private
      # The column would round a fifth decimal away on write. Refuse it
      # instead, by looking at the amount as it was given.
      def amount_within_precision
        given = BigDecimal(amount_before_type_cast.to_s, exception: false)

        if given && !MolliePay.amount_within_precision?(given)
          errors.add(:amount, "must be at most #{MolliePay::MAX_AMOUNT.to_i} with at most #{MolliePay::MONEY_SCALE} decimal places")
        end
      end
  end
end
