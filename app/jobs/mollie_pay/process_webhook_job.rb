module MolliePay
  class ProcessWebhookJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on Mollie::ResourceNotFoundError
    discard_on ActiveRecord::RecordNotFound

    def perform(event_id)
      event = WebhookEvent.find(event_id)
      return if event.processed?

      event.process!
    end
  end
end
