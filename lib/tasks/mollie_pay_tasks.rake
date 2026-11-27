namespace :mollie_pay do
  namespace :request_signing do
    desc "Generate an Ed25519 key pair for request signing and print both keys, once"
    task :generate do
      private_key, public_key = MolliePay::RequestSignature.generate_key_pair

      puts "Public key. Paste it into the \"Public key\" field of the API key in the"
      puts "Mollie dashboard (Developers > API keys). It is not a secret."
      puts
      puts public_key
      puts
      puts "Private key. Store it as a secret and nowhere else: it is shown once and"
      puts "is not saved. Set it as MOLLIE_REQUEST_SIGNING_KEY, or put it in the"
      puts "encrypted credentials. See https://github.com/peterberkenbosch/mollie_pay/blob/master/docs/request-signing.md"
      puts
      puts MolliePay::RequestSignature.single_line(private_key)
    end

    desc "Print the public key that belongs to the configured private key"
    task public_key: :environment do
      public_key = MolliePay.configuration.request_signing_public_key

      abort "No request_signing_key is configured." if public_key.nil?
      puts public_key
    end

    desc "Ask Mollie whether it enforces signing for the API key and accepts this app's signature"
    task verify: :environment do
      case MolliePay::RequestSignature.status
      when :accepted
        puts "OK: Mollie refuses unsigned requests for this API key and accepts this app's signature."
      when :not_enforced
        abort "Not enforced: Mollie accepts unsigned requests for this API key, so no public key is registered on it. " \
          "Register the output of mollie_pay:request_signing:public_key in the Mollie dashboard."
      when :refused
        abort "Refused: Mollie enforces signing and does not accept this app's signature. The public key registered " \
          "at Mollie is not this private key's, the API key is wrong, or this machine's clock is more than 5 minutes off."
      when :not_configured
        abort "No request_signing_key is configured."
      end
    end
  end
end
