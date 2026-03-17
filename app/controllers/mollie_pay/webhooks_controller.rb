module MolliePay
  class WebhooksController < ApplicationController
    MOLLIE_ID_FORMAT = /\A(tr|sub|re)_[a-zA-Z0-9]+\z/

    skip_forgery_protection

    def create
      mollie_id = params.expect(:id)

      if mollie_id.match?(MOLLIE_ID_FORMAT)
        ProcessWebhookJob.perform_later(mollie_id)
        head :ok
      else
        head :unprocessable_entity
      end
    rescue ActionController::ParameterMissing
      head :unprocessable_entity
    end
  end
end
