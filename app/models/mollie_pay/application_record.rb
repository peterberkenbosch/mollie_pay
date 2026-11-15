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
      def amount_within_precision
        if amount && !MolliePay.amount_within_precision?(amount)
          errors.add(:amount, "must be finite, with at most #{MolliePay::MAX_INTEGER_DIGITS} digits before and #{MolliePay::MAX_DECIMAL_PLACES} after the decimal point")
        end
      end
  end
end
