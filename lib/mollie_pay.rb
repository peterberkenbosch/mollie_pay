require "mollie-api-ruby"
require "mollie/sales_invoice"
require "mollie_pay/version"
require "mollie_pay/errors"
require "mollie_pay/configuration"
require "mollie_pay/webhook_signature"
require "mollie_pay/decimal_money_type"
require "mollie_pay/engine"

module MolliePay
  # Currencies Mollie expects without decimals ("1000", not "1000.00").
  ZERO_DECIMAL_CURRENCIES = %w[ ISK JPY ].freeze

  # Amounts are never rounded before storing, but they are bounded: anything
  # with more digits than this is refused.
  MAX_INTEGER_DIGITS = 12
  MAX_DECIMAL_PLACES = 8

  # Convert an exact amount to Mollie's wire format { currency:, value: "10.00" }.
  # This is the one place an amount is rounded: half up, to the currency's
  # minor unit, in BigDecimal and never through a Float.
  #
  #   MolliePay.mollie_amount(BigDecimal("10.125"))            # => { currency: "EUR", value: "10.13" }
  #   MolliePay.mollie_amount(BigDecimal("1000"), currency: "JPY") # => { currency: "JPY", value: "1000" }
  #
  def self.mollie_amount(amount, currency: configuration.currency)
    decimal = BigDecimal(amount.to_s)
    raise InvalidAmount, "#{amount} is not an amount Mollie can take" unless amount_within_precision?(decimal)

    places = ZERO_DECIMAL_CURRENCIES.include?(currency) ? 0 : 2
    whole, fraction = decimal.round(places, BigDecimal::ROUND_HALF_UP).to_s("F").split(".")

    { currency: currency, value: places.zero? ? whole : "#{whole}.#{fraction.ljust(places, "0")}" }
  end

  def self.amount_within_precision?(decimal)
    decimal.finite? &&
      decimal.scale <= MAX_DECIMAL_PLACES &&
      decimal.precision - decimal.scale <= MAX_INTEGER_DIGITS
  end

  # List enabled payment methods. Optionally filter by amount and currency.
  # Returns Mollie SDK objects directly (Mollie::List of Mollie::Method).
  #
  #   MolliePay.payment_methods
  #   MolliePay.payment_methods(amount: BigDecimal("10.00"), locale: "nl_NL")
  #   MolliePay.payment_methods(amount: BigDecimal("10.00"), currency: "EUR", include: "pricing")
  #
  def self.payment_methods(amount: nil, currency: nil, locale: nil, **options)
    params = options
    if amount
      params[:amount] = mollie_amount(amount, currency: currency || configuration.currency)
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

  # Create a sales invoice on Mollie (beta).
  # Accepts snake_case Ruby hashes — keys are camelized before sending.
  # Line item unit_price accepts a BigDecimal and is converted to Mollie format.
  #
  #   MolliePay.create_sales_invoice(
  #     status: "issued",
  #     recipient: { type: "consumer", given_name: "Jane", family_name: "Doe", email: "jane@example.com" },
  #     lines: [{ description: "Pro plan", quantity: 1, vat_rate: "21.00", unit_price: BigDecimal("89.00") }],
  #     email_details: { subject: "Your invoice", body: "Please pay" }
  #   )
  #
  def self.create_sales_invoice(status:, recipient:, lines:, **options)
    params = deep_camelize_keys(options)
    params[:status] = status
    params[:recipient] = deep_camelize_keys(recipient)
    params[:lines] = lines.map { |line| build_sales_invoice_line(line) }
    Mollie::SalesInvoice.create(params, idempotency_key: SecureRandom.uuid)
  end

  # Get a single sales invoice by ID.
  #
  #   MolliePay.sales_invoice("invoice_abc123")
  #
  def self.sales_invoice(id)
    Mollie::SalesInvoice.get(id)
  end

  # List all sales invoices.
  #
  #   MolliePay.sales_invoices
  #
  def self.sales_invoices(**options)
    Mollie::SalesInvoice.all(options)
  end

  # Update a sales invoice.
  #
  #   MolliePay.update_sales_invoice("invoice_abc123", memo: "Updated memo")
  #
  def self.update_sales_invoice(id, **attrs)
    params = deep_camelize_keys(attrs.except(:recipient, :lines))
    params[:recipient] = deep_camelize_keys(attrs[:recipient]) if attrs[:recipient]
    params[:lines] = attrs[:lines].map { |line| build_sales_invoice_line(line) } if attrs[:lines]
    Mollie::SalesInvoice.update(id, params)
  end

  # Delete a draft sales invoice.
  #
  #   MolliePay.delete_sales_invoice("invoice_abc123")
  #
  def self.delete_sales_invoice(id)
    Mollie::SalesInvoice.delete(id)
  end

  def self.build_sales_invoice_line(line)
    built = deep_camelize_keys(line)
    if built[:unitPrice].is_a?(Numeric)
      built[:unitPrice] = mollie_amount(built[:unitPrice])
    end
    built
  end
  private_class_method :build_sales_invoice_line

  def self.deep_camelize_keys(hash)
    hash.each_with_object({}) do |(key, value), result|
      camelized_key = Mollie::Util.camelize(key)
      result[camelized_key.to_sym] = if value.is_a?(Hash)
        deep_camelize_keys(value)
      elsif value.is_a?(Array)
        value.map { |v| v.is_a?(Hash) ? deep_camelize_keys(v) : v }
      else
        value
      end
    end
  end
  private_class_method :deep_camelize_keys
end
