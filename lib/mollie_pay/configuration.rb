module MolliePay
  class ConfigurationError < Error; end

  class Configuration
    attr_accessor :api_key
    attr_accessor :host
    attr_accessor :default_redirect_path
    attr_accessor :currency

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

    def default_redirect_url
      return nil if default_redirect_path.blank?

      "#{host_without_trailing_slash}#{default_redirect_path}"
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
