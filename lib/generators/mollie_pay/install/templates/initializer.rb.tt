MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"] # e.g. "https://yourapp.com"
  config.default_redirect_path = "/payments/:id"
  config.currency              = "EUR"

  # Sign every request to Mollie, once a public key is registered on the API
  # key. bin/rails mollie_pay:request_signing:generate makes the key pair; where
  # to keep the private key is in
  # https://github.com/peterberkenbosch/mollie_pay/blob/master/docs/request-signing.md
  # config.request_signing_key = ENV["MOLLIE_REQUEST_SIGNING_KEY"]
end
