require "openssl"

module MolliePay
  module WebhookSignature
    module_function

    def verify!(payload, signature_header, secrets)
      raise MolliePay::InvalidSignature, "Missing signature" if signature_header.blank?
      raise MolliePay::InvalidSignature, "Invalid signature format" unless signature_header.start_with?("sha256=")

      provided = signature_header.delete_prefix("sha256=")

      verified = Array(secrets).any? do |secret|
        calculated = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
        ActiveSupport::SecurityUtils.secure_compare(calculated, provided)
      end

      raise MolliePay::InvalidSignature, "Invalid signature" unless verified
    end
  end
end
