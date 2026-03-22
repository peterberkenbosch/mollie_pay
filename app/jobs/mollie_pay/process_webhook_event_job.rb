module MolliePay
  class ProcessWebhookEventJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(event)
      Rails.logger.info("[MolliePay] Received webhook event: #{event['type']} (#{event['entityId']})")
    end
  end
end
