module MolliePay
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def create
      mollie_id = params.expect(:id)

      unless WebhookEvent.pending.exists?(mollie_id: mollie_id)
        event = WebhookEvent.create!(mollie_id: mollie_id)
        ProcessWebhookJob.perform_later(event.id)
      end

      head :ok
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid
      head :unprocessable_entity
    end
  end
end
