module MolliePay
  class Engine < ::Rails::Engine
    isolate_namespace MolliePay

    initializer "mollie_pay.configure_mollie_client" do
      ActiveSupport.on_load(:active_record) do
        ::Mollie::Client.configure do |client|
          client.api_key = MolliePay.configuration.api_key
        end
      end
    end

    initializer "mollie_pay.sign_mollie_requests" do
      ::Mollie::Client.prepend(MolliePay::RequestSignature::Client)

      # Reads the key at boot, so a bad key fails here and not on the first payment.
      config.after_initialize { MolliePay.configuration.request_signing_private_key }
    end

    initializer "mollie_pay.warn_missing_webhook_secret", after: :finisher_hook do
      config.after_initialize do
        if MolliePay.configuration.webhook_signing_secrets.nil?
          Rails.logger.warn(
            "[MolliePay] webhook_signing_secret is not configured. " \
            "Next-gen webhook events at /webhook_events will be accepted without signature verification."
          )
        end
      end
    end
  end
end
