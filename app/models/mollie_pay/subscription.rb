module MolliePay
  class Subscription < ApplicationRecord
    STATUSES = %w[ pending active suspended canceled completed ].freeze

    belongs_to :customer
    has_many   :payments, dependent: :nullify

    validates :mollie_id, presence: true, uniqueness: true
    validates :status,    inclusion: { in: STATUSES }
    validates :amount,    presence: true, numericality: { greater_than: 0 }
    validates :currency,  presence: true
    validates :interval,  presence: true

    scope :active,     -> { where(status: "active") }
    scope :pending,    -> { where(status: "pending") }
    scope :suspended,  -> { where(status: "suspended") }
    scope :canceled,   -> { where(status: "canceled") }
    scope :completed,  -> { where(status: "completed") }

    def self.record_from_mollie(ms)
      customer = Customer.includes(:owner).find_by!(mollie_id: ms.customer_id)
      subscription = find_or_initialize_by(mollie_id: ms.id)
      previous_status = subscription.status

      subscription.update!(
        customer:    customer,
        status:      ms.status,
        amount:      mollie_value_to_cents(ms.amount),
        currency:    ms.amount.currency,
        interval:    ms.interval,
        canceled_at: ms.status == "canceled" && !subscription.canceled_at ? Time.current : subscription.canceled_at
      )

      subscription.notify_billable if subscription.status != previous_status
      subscription
    end

    def notify_billable
      billable = customer.owner

      case status
      when "canceled"  then billable.on_mollie_subscription_canceled(self)
      when "suspended" then billable.on_mollie_subscription_suspended(self)
      when "completed" then billable.on_mollie_subscription_completed(self)
      end
    end

    def mollie_record
      Mollie::Subscription.get(mollie_id, customer_id: customer.mollie_id)
    end

    def active?
      status == "active"
    end

    def canceled?
      status == "canceled"
    end

    def amount_decimal
      amount / 100.0
    end
  end
end
