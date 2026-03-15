module MolliePay
  class Mandate < ApplicationRecord
    STATUSES = %w[ pending valid invalid ].freeze

    belongs_to :customer

    validates :mollie_id, presence: true, uniqueness: true
    validates :status,    inclusion: { in: STATUSES }
    validates :method,    presence: true

    scope :valid_status, -> { where(status: "valid") }
    scope :pending,      -> { where(status: "pending") }

    def self.record_from_mollie_payment(payment, mollie_payment = nil)
      mollie_payment ||= payment.mollie_record
      return unless mollie_payment.mandate_id

      customer = payment.customer
      mollie_mandate = Mollie::Customer::Mandate.get(mollie_payment.mandate_id, customer_id: customer.mollie_id)

      mandate = find_or_initialize_by(mollie_id: mollie_mandate.id)
      was_valid = mandate.valid_status?

      mandate.update!(
        customer:    customer,
        status:      mollie_mandate.status,
        method:      mollie_mandate.method,
        mandated_at: mollie_mandate.status == "valid" && !was_valid ? Time.current : mandate.mandated_at
      )

      customer.owner.on_mollie_mandate_created(mandate) if mandate.valid_status? && !was_valid
      mandate
    end

    def mollie_record
      Mollie::Customer::Mandate.get(mollie_id, customer_id: customer.mollie_id)
    end

    def valid_status?
      status == "valid"
    end
  end
end
