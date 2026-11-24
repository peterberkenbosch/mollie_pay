module MolliePay
  class Mandate < ApplicationRecord
    STATUSES = %w[ pending valid invalid ].freeze

    belongs_to :customer

    validates :mollie_id, presence: true, uniqueness: true
    validates :status,    inclusion: { in: STATUSES }
    validates :method,    presence: true

    scope :valid_status, -> { where(status: "valid") }
    scope :pending,      -> { where(status: "pending") }

    def self.record_from_mollie_mandate(mollie_mandate, customer)
      mandate = find_or_initialize_by(mollie_id: mollie_mandate.id)

      if mandate.new_record?
        mandate.update!(
          customer:    customer,
          status:      mollie_mandate.status,
          method:      mollie_mandate.method,
          mandated_at: mollie_mandate.status == "valid" ? Time.current : nil
        )
        became_valid = mandate.valid_status?
      else
        mandate.update!(customer: customer, method: mollie_mandate.method)
        became_valid = mandate.record_status(mollie_mandate.status)
      end

      customer.owner.on_mollie_mandate_created(mandate) if became_valid
      mandate
    end

    def self.record_from_mollie_payment(payment, mollie_payment = nil)
      mollie_payment ||= payment.mollie_record
      return unless mollie_payment.mandate_id

      customer = payment.customer
      mollie_mandate = Mollie::Customer::Mandate.get(mollie_payment.mandate_id, customer_id: customer.mollie_id)
      mandate = record_from_mollie_mandate(mollie_mandate, customer)
      RefreshPendingMandateJob.perform_later(mandate) if mandate.pending?
      mandate
    end

    # Mollie has no mandate webhooks. A mandate that was still pending when its
    # first payment was paid is re-fetched by RefreshPendingMandateJob, and on
    # later webhooks for that payment when Mollie sends any.
    def self.refresh_pending_from_mollie_payment(payment, mollie_payment)
      if pending.exists?(customer: payment.customer, mollie_id: mollie_payment.mandate_id)
        record_from_mollie_payment(payment, mollie_payment)
      end
    end

    def mollie_record
      Mollie::Customer::Mandate.get(mollie_id, customer_id: customer.mollie_id)
    end

    # Stores a status Mollie reported and returns whether this call moved the
    # mandate to valid. The move is one conditional UPDATE, so when the refresh
    # job and a payment webhook both saw the mandate pending, only one of them
    # fires on_mollie_mandate_created. Mollie never takes a valid mandate back
    # to pending, so a pending answer that lands after valid is stale.
    def record_status(mollie_status)
      unsettled = self.class.where(id: id).where.not(status: "valid")
      became_valid = false

      case mollie_status
      when "valid"
        now = Time.current
        became_valid = unsettled.update_all([ "status = ?, mandated_at = COALESCE(mandated_at, ?), updated_at = ?", "valid", now, now ]) == 1
      when "pending"
        unsettled.update_all(status: "pending", updated_at: Time.current)
      else
        update!(status: mollie_status)
      end

      reload
      became_valid
    end

    def valid_status?
      status == "valid"
    end

    def pending?
      status == "pending"
    end
  end
end
