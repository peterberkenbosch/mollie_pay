module MolliePay
  class ConfigurationError < Error; end

  class Configuration
    attr_accessor :api_key
    attr_accessor :host
    attr_accessor :default_redirect_path
    attr_accessor :currency
    attr_accessor :webhook_signing_secret
    attr_accessor :request_signing_key

    def initialize
      @currency = "EUR"
    end

    def validate!
      raise ConfigurationError, "MolliePay.configuration.api_key is required" if api_key.blank?
      raise ConfigurationError, "MolliePay.configuration.host is required" if host.blank?
    end

    def webhook_url
      "#{host_without_trailing_slash}#{MolliePay::Engine.routes.url_helpers.webhooks_path}"
    end

    def redirect_url_for(payment)
      return nil if default_redirect_path.blank?

      path = default_redirect_path.gsub(":id", payment.id.to_s)
      "#{host_without_trailing_slash}#{path}"
    end

    # Returns nil (not configured) or a non-empty array of secrets.
    # Treats nil, "", and [] as "not configured" to prevent silent rejection
    # when an empty array is passed.
    def webhook_signing_secrets
      secrets = Array(webhook_signing_secret).reject(&:blank?)
      secrets.empty? ? nil : secrets
    end

    # Returns nil (not configured) or the Ed25519 private key that signs every
    # request to Mollie. request_signing_key holds it as PEM, as PEM with its
    # line breaks written as "\n", or as the one line of base64 between the
    # PEM's first and last line, which is the form a secret store and an
    # environment variable hold without trouble.
    def request_signing_private_key
      return nil if request_signing_key.blank?
      return @request_signing_private_key if @request_signing_private_key_source == request_signing_key

      key = RequestSignature.read_key(request_signing_key)
      raise ConfigurationError, "MolliePay.configuration.request_signing_key must be an Ed25519 private key" unless key.oid == "ED25519"
      raise ConfigurationError, "MolliePay.configuration.request_signing_key holds the public key; it needs the private one" unless RequestSignature.private?(key)

      @request_signing_private_key_source = request_signing_key
      @request_signing_private_key = key
    rescue OpenSSL::PKey::PKeyError
      raise ConfigurationError, "MolliePay.configuration.request_signing_key is not a readable private key"
    end

    # The public half of the configured key as PEM: what is registered at
    # Mollie. Nil when no key is configured.
    def request_signing_public_key
      request_signing_private_key&.public_to_pem
    end

    def inspect
      "#<MolliePay::Configuration host=#{host.inspect} default_redirect_path=#{default_redirect_path.inspect} currency=#{currency.inspect} api_key=[FILTERED]>"
    end

    private

    def host_without_trailing_slash
      host&.chomp("/")
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end
  end
end
