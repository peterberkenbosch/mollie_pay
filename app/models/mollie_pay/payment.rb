module MolliePay
  class Payment < ApplicationRecord
    STATUSES = %w[ open pending authorized paid failed canceled expired ].freeze
    SEQUENCE_TYPES = %w[ oneoff first recurring ].freeze

    belongs_to :customer
    belongs_to :subscription, optional: true
    has_many   :refunds, dependent: :destroy

    # amount_remaining uses nil-semantics: nil = "never fetched from Mollie",
    # 0 = "fully captured/refunded". Only populated when Mollie includes the field.

    validates :mollie_id,     uniqueness: true, allow_nil: true
    validates :status,        inclusion: { in: STATUSES }
    validates :sequence_type, inclusion: { in: SEQUENCE_TYPES }
    validates :amount,        presence: true, numericality: { greater_than: 0 }
    validates :currency,      presence: true

    scope :paid,      -> { where(status: "paid") }
    scope :failed,    -> { where(status: "failed") }
    scope :open,      -> { where(status: "open") }
    scope :recurring, -> { where(sequence_type: "recurring") }
    scope :first_payments, -> { where(sequence_type: "first") }

    def self.record_from_mollie(mp)
      customer = Customer.includes(:owner).find_by!(mollie_id: mp.customer_id)

      payment = find_or_initialize_by(mollie_id: mp.id)
      previous_status = payment.status

      # Link recurring payments to their subscription
      if mp.subscription_id.present? && payment.subscription_id.nil?
        subscription = Subscription.find_by(mollie_id: mp.subscription_id)
        payment.subscription = subscription if subscription
      end

      payment.update!(
        customer:            customer,
        status:              mp.status,
        amount:              mollie_value_to_cents(mp.amount),
        currency:            mp.amount.currency,
        sequence_type:       mp.sequence_type.presence || "oneoff",
        paid_at:             mp.status == "paid" && !payment.paid_at ? Time.current : payment.paid_at,
        authorized_at:       mp.status == "authorized" && !payment.authorized_at ? Time.current : payment.authorized_at,
        failed_at:           mp.status == "failed" && !payment.failed_at ? Time.current : payment.failed_at,
        canceled_at:         mp.status == "canceled" && !payment.canceled_at ? Time.current : payment.canceled_at,
        expired_at:          mp.status == "expired" && !payment.expired_at ? Time.current : payment.expired_at,
        amount_refunded:     mp.amount_refunded ? mollie_value_to_cents(mp.amount_refunded) : payment.amount_refunded,
        amount_remaining:    mp.amount_remaining ? mollie_value_to_cents(mp.amount_remaining) : payment.amount_remaining,
        amount_captured:     mp.amount_captured ? mollie_value_to_cents(mp.amount_captured) : payment.amount_captured,
        amount_charged_back: mp.amount_charged_back ? mollie_value_to_cents(mp.amount_charged_back) : payment.amount_charged_back
      )

      payment.notify_billable(mp) if payment.status != previous_status
      payment
    rescue ActiveRecord::RecordNotUnique
      find_by!(mollie_id: mp.id)
    end

    def notify_billable(mollie_payment = nil)
      billable = customer.owner

      case status
      when "paid"
        if first_payment?
          Mandate.record_from_mollie_payment(self, mollie_payment)
          billable.on_mollie_first_payment_paid(self)
        elsif recurring?
          billable.on_mollie_subscription_charged(self)
        else
          billable.on_mollie_payment_paid(self)
        end
      when "authorized" then billable.on_mollie_payment_authorized(self)
      when "failed"     then billable.on_mollie_payment_failed(self)
      when "canceled"   then billable.on_mollie_payment_canceled(self)
      when "expired"    then billable.on_mollie_payment_expired(self)
      end
    end

    def mollie_record
      Mollie::Payment.get(mollie_id)
    end

    def paid?
      status == "paid"
    end

    def failed?
      status == "failed"
    end

    def first_payment?
      sequence_type == "first"
    end

    def recurring?
      sequence_type == "recurring"
    end

    def amount_decimal
      amount / 100.0
    end

    # Mollie expects amount as { currency: "EUR", value: "10.00" }
    def mollie_amount
      { currency: currency, value: format("%.2f", amount_decimal) }
    end
  end
end
