module MolliePay
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    def self.mollie_value_to_cents(mollie_amount)
      (mollie_amount.value.to_d * 100).to_i
    end
  end
end
