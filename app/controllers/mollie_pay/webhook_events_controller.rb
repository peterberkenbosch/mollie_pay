module MolliePay
  class WebhookEventsController < ApplicationController
    skip_forgery_protection

    # Without a signing secret an event cannot be verified, so the endpoint
    # acts as if it is not there.
    before_action :require_signing_secret

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

      def require_signing_secret
        head :not_found if MolliePay.configuration.webhook_signing_secrets.nil?
      end

      def verify_signature!(raw_body)
        MolliePay::WebhookSignature.verify!(
          raw_body,
          request.headers["X-Mollie-Signature"],
          MolliePay.configuration.webhook_signing_secrets
        )
      end
  end
end
