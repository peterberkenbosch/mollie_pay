require "mollie-api-ruby"
require "mollie_pay/version"
require "mollie_pay/errors"
require "mollie_pay/configuration"
require "mollie_pay/webhook_signature"
require "mollie_pay/engine"

module MolliePay
  # List enabled payment methods. Optionally filter by amount and currency.
  # Returns Mollie SDK objects directly (Mollie::List of Mollie::Method).
  #
  #   MolliePay.payment_methods
  #   MolliePay.payment_methods(amount: 1000, locale: "nl_NL")
  #   MolliePay.payment_methods(amount: 1000, currency: "EUR", include: "pricing")
  #
  def self.payment_methods(amount: nil, currency: nil, locale: nil, **options)
    params = options
    if amount
      params[:amount] = {
        currency: currency || configuration.currency,
        value:    format("%.2f", amount / 100.0)
      }
    end
    params[:locale] = locale if locale
    Mollie::Method.all(params)
  end

  # Get a single payment method by its ID.
  # Returns a Mollie::Method object.
  #
  #   MolliePay.payment_method("ideal")
  #   MolliePay.payment_method("creditcard", locale: "nl_NL")
  #
  def self.payment_method(id, **options)
    Mollie::Method.get(id, options)
  end
end
