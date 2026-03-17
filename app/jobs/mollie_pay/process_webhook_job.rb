module MolliePay
  class ProcessWebhookJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on Mollie::ResourceNotFoundError
    discard_on ActiveRecord::RecordNotFound

    def perform(mollie_id)
      case mollie_id
      when /\Atr_/  then Payment.record_from_mollie(Mollie::Payment.get(mollie_id))
      when /\Asub_/ then sync_subscription(mollie_id)
      when /\Are_/  then sync_refund(mollie_id)
      end
    end

    private

      def sync_subscription(mollie_id)
        subscription = Subscription.find_by!(mollie_id: mollie_id)
        Subscription.record_from_mollie(
          Mollie::Subscription.get(mollie_id, customer_id: subscription.customer.mollie_id)
        )
      end

      def sync_refund(mollie_id)
        refund = Refund.find_by!(mollie_id: mollie_id)
        Refund.record_from_mollie(
          Mollie::Refund.get(mollie_id, payment_id: refund.payment.mollie_id)
        )
      end
  end
end
