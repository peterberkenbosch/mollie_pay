module MolliePay
  class Refund < ApplicationRecord
    STATUSES = %w[ queued pending processing refunded failed ].freeze

    belongs_to :payment

    validates :mollie_id, presence: true, uniqueness: true
    validates :status,    inclusion: { in: STATUSES }
    validates :amount,    presence: true, numericality: { greater_than: 0 }
    validates :currency,  presence: true

    scope :refunded,    -> { where(status: "refunded") }
    scope :processing,  -> { where(status: "processing") }

    def self.record_from_mollie(mr)
      payment = Payment.includes(customer: :owner).find_by!(mollie_id: mr.payment_id)
      refund  = find_or_initialize_by(mollie_id: mr.id)
      previous_status = refund.status

      refund.update!(
        payment:     payment,
        status:      mr.status,
        amount:      mollie_value_to_cents(mr.amount),
        currency:    mr.amount.currency,
        refunded_at: mr.status == "refunded" && !refund.refunded_at ? Time.current : refund.refunded_at
      )

      if refund.status == "refunded" && previous_status != "refunded"
        payment.customer.owner.on_mollie_refund_processed(refund)
      end
      refund
    rescue ActiveRecord::RecordNotUnique
      find_by!(mollie_id: mr.id)
    end

    def mollie_record
      Mollie::Refund.get(mollie_id, payment_id: payment.mollie_id)
    end

    def refunded?
      status == "refunded"
    end

    def amount_decimal
      amount / 100.0
    end

    def mollie_amount
      { currency: currency, value: format("%.2f", amount_decimal) }
    end
  end
end
