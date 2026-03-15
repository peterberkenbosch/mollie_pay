module MolliePay
  class ConfigurationError < Error; end

  class Configuration
    attr_accessor :api_key
    attr_accessor :webhook_url
    attr_accessor :currency

    def initialize
      @currency = "EUR"
    end

    def validate!
      raise ConfigurationError, "MolliePay.configuration.api_key is required" if api_key.blank?
      raise ConfigurationError, "MolliePay.configuration.webhook_url is required" if webhook_url.blank?
    end

    def inspect
      "#<MolliePay::Configuration webhook_url=#{webhook_url.inspect} currency=#{currency.inspect} api_key=[FILTERED]>"
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
