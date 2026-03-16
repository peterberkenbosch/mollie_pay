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
  end
end
