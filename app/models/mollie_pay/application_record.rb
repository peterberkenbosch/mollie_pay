module MolliePay
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    include MolliePay::HasUuid

    # Mollie sends amounts as { currency:, value: "10.00" } (a decimal string).
    # Parse straight to exact BigDecimal; never through cents or Float.
    def self.mollie_value_to_decimal(mollie_amount)
      BigDecimal(mollie_amount.value)
    end
  end
end
