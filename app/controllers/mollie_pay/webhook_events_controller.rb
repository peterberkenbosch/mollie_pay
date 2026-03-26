module MolliePay
  class WebhookEventsController < ApplicationController
    skip_forgery_protection

    def create
      raw_body = request.raw_post
      head :bad_request and return if raw_body.blank?

      verify_signature!(raw_body)

      event = JSON.parse(raw_body)

      if event["id"].present? && event["type"].present?
        ProcessWebhookEventJob.perform_later(event)
        head :ok
      else
        head :unprocessable_entity
      end
    rescue JSON::ParserError
      head :bad_request
    rescue MolliePay::InvalidSignature => e
      Rails.logger.warn("[MolliePay] Webhook signature verification failed: #{e.message}")
      head :bad_request
    end

    private

      def verify_signature!(raw_body)
        secrets = MolliePay.configuration.webhook_signing_secrets
        return if secrets.nil?

        MolliePay::WebhookSignature.verify!(
          raw_body,
          request.headers["X-Mollie-Signature"],
          secrets
        )
      end
  end
end
