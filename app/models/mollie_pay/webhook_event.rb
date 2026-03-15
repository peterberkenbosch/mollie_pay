module MolliePay
  class WebhookEvent < ApplicationRecord
    validates :mollie_id, presence: true,
                          format: { with: /\A(tr|sub|re)_[a-zA-Z0-9]+\z/ }

    scope :processed, -> { where.not(processed_at: nil) }
    scope :failed,    -> { where.not(failed_at: nil) }
    scope :pending,   -> { where(processed_at: nil, failed_at: nil) }

    def process!
      update!(failed_at: nil, error: nil) if failed?

      mollie_object = fetch_from_mollie
      sync_from_mollie(mollie_object)
      update!(resource_type: resolved_resource_type(mollie_object), processed_at: Time.current)
    rescue Mollie::Exception, ActiveRecord::ActiveRecordError, ArgumentError => e
      update!(failed_at: Time.current, error: e.message.to_s.truncate(500))
      raise
    end

    def processed?
      processed_at.present?
    end

    def failed?
      failed_at.present?
    end

    private

      def fetch_from_mollie
        case mollie_id
        when /\Atr_/  then Mollie::Payment.get(mollie_id)
        when /\Asub_/ then fetch_subscription_from_mollie
        when /\Are_/  then fetch_refund_from_mollie
        else raise ArgumentError, "Unknown Mollie resource: #{mollie_id}"
        end
      end

      def fetch_subscription_from_mollie
        subscription = Subscription.find_by!(mollie_id: mollie_id)
        Mollie::Subscription.get(mollie_id, customer_id: subscription.customer.mollie_id)
      end

      def fetch_refund_from_mollie
        refund = Refund.find_by!(mollie_id: mollie_id)
        Mollie::Refund.get(mollie_id, payment_id: refund.payment.mollie_id)
      end

      def resolved_resource_type(mollie_object)
        case mollie_object
        when Mollie::Payment      then "payment"
        when Mollie::Subscription then "subscription"
        when Mollie::Refund       then "refund"
        end
      end

      def sync_from_mollie(mollie_object)
        case mollie_object
        when Mollie::Payment      then Payment.record_from_mollie(mollie_object)
        when Mollie::Subscription then Subscription.record_from_mollie(mollie_object)
        when Mollie::Refund       then Refund.record_from_mollie(mollie_object)
        end
      end
  end
end
