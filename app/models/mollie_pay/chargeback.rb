module MolliePay
  class Chargeback < ApplicationRecord
    belongs_to :payment

    validates :mollie_id, presence: true, uniqueness: true
    validates :amount,    presence: true, numericality: { greater_than: 0 }
    validates :currency,  presence: true

    def self.sync_for_payment(payment)
      mollie_chargebacks = payment.mollie_record.chargebacks
      return if mollie_chargebacks.blank?

      billable = payment.customer.owner
      events = []

      mollie_chargebacks.each do |mc|
        chargeback = find_or_initialize_by(mollie_id: mc.id)
        was_new = chargeback.new_record?
        was_reversed = chargeback.reversed_at

        chargeback.update!(
          payment:           payment,
          amount:            mollie_value_to_cents(mc.amount),
          currency:          mc.amount.currency,
          reason:            mc.reason&.to_s,
          created_at_mollie: mc.created_at,
          reversed_at:       mc.reversed_at
        )

        if was_new
          events << [ :received, chargeback ]
        elsif chargeback.reversed_at.present? && was_reversed.nil?
          events << [ :reversed, chargeback ]
        end
      rescue ActiveRecord::RecordNotUnique
        find_by!(mollie_id: mc.id)
      end

      events.each do |type, chargeback|
        case type
        when :received then billable.on_mollie_chargeback_received(chargeback)
        when :reversed then billable.on_mollie_chargeback_reversed(chargeback)
        end
      end
    end

    def reversed?
      reversed_at.present?
    end

    def mollie_record
      Mollie::Payment::Chargeback.get(mollie_id, payment_id: payment.mollie_id)
    end

    def amount_decimal
      amount / 100.0
    end

    def mollie_amount
      { currency: currency, value: format("%.2f", amount_decimal) }
    end
  end
end
