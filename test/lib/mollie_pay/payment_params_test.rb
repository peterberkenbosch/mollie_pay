require "test_helper"

class MolliePay::PaymentParamsTest < ActiveSupport::TestCase
  test "build_payment_params converts line money fields to Mollie format" do
    params = MolliePay.build_payment_params(
      lines: [ {
        description: "Widget",
        quantity:    1,
        unit_price:  BigDecimal("121.00"),
        total_amount: BigDecimal("121.00"),
        vat_rate:    "21.00",
        vat_amount:  BigDecimal("21.00")
      } ]
    )

    line = params[:lines].first
    assert_equal "Widget", line[:description]
    assert_equal 1, line[:quantity]
    assert_equal({ currency: "EUR", value: "121.00" }, line[:unitPrice])
    assert_equal({ currency: "EUR", value: "121.00" }, line[:totalAmount])
    assert_equal "21.00", line[:vatRate]
    assert_equal({ currency: "EUR", value: "21.00" }, line[:vatAmount])
  end

  test "build_payment_params converts discount_amount to Mollie format" do
    params = MolliePay.build_payment_params(
      lines: [ { description: "Widget", quantity: 1, unit_price: BigDecimal("10.00"), total_amount: BigDecimal("5.00"), discount_amount: BigDecimal("5.00") } ]
    )

    assert_equal({ currency: "EUR", value: "5.00" }, params[:lines].first[:discountAmount])
  end

  test "build_payment_params passes wire-format money hashes through unchanged" do
    params = MolliePay.build_payment_params(
      lines: [ { description: "Widget", quantity: 1, unit_price: { currency: "EUR", value: "10.00" }, total_amount: { currency: "EUR", value: "10.00" } } ]
    )

    assert_equal({ currency: "EUR", value: "10.00" }, params[:lines].first[:unitPrice])
  end

  test "build_payment_params sends non-money line fields as given" do
    params = MolliePay.build_payment_params(
      lines: [ { description: "Widget", quantity: 3, type: "physical", sku: "W-1", unit_price: BigDecimal("10.00"), total_amount: BigDecimal("30.00") } ]
    )

    line = params[:lines].first
    assert_equal 3, line[:quantity]
    assert_equal "physical", line[:type]
    assert_equal "W-1", line[:sku]
  end

  test "build_payment_params camelizes billing address keys" do
    params = MolliePay.build_payment_params(billing_address: { street_and_number: "A 1", postal_code: "1234 AB" })

    assert_equal({ streetAndNumber: "A 1", postalCode: "1234 AB" }, params[:billingAddress])
  end

  test "build_payment_params camelizes shipping address keys" do
    params = MolliePay.build_payment_params(shipping_address: { given_name: "Jan", country: "NL" })

    assert_equal({ givenName: "Jan", country: "NL" }, params[:shippingAddress])
  end

  test "build_payment_params passes capture_mode and locale" do
    params = MolliePay.build_payment_params(capture_mode: "manual", locale: "nl_NL")

    assert_equal "manual", params[:captureMode]
    assert_equal "nl_NL", params[:locale]
  end

  test "build_payment_params returns an empty hash without arguments" do
    assert_equal({}, MolliePay.build_payment_params)
  end

  test "build_payment_params omits keys for nil arguments" do
    params = MolliePay.build_payment_params(lines: nil, billing_address: nil, shipping_address: nil, capture_mode: nil, locale: nil)

    assert_equal({}, params)
  end
end
