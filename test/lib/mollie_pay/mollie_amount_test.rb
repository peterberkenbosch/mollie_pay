require "test_helper"

class MolliePay::MollieAmountTest < ActiveSupport::TestCase
  test "formats an amount with two decimals" do
    assert_equal({ currency: "EUR", value: "10.00" }, MolliePay.mollie_amount(BigDecimal("10")))
    assert_equal({ currency: "EUR", value: "10.10" }, MolliePay.mollie_amount(BigDecimal("10.1")))
    assert_equal({ currency: "EUR", value: "0.05" }, MolliePay.mollie_amount(BigDecimal("0.05")))
  end

  test "rounds half up, where a float would round down" do
    assert_equal "10.13", MolliePay.mollie_amount(BigDecimal("10.125"))[:value]
    assert_equal "1.01", MolliePay.mollie_amount(BigDecimal("1.005"))[:value]
    assert_equal "4.99", MolliePay.mollie_amount(BigDecimal("4.9949"))[:value]
  end

  test "sends zero-decimal currencies without decimals" do
    assert_equal({ currency: "JPY", value: "1000" }, MolliePay.mollie_amount(BigDecimal("1000"), currency: "JPY"))
    assert_equal({ currency: "ISK", value: "1001" }, MolliePay.mollie_amount(BigDecimal("1000.5"), currency: "ISK"))
  end

  test "refuses amounts that are not finite or have too many digits" do
    [ "Infinity", "NaN", "1e1000000", "1000000000000", "0.123456789" ].each do |amount|
      assert_raises(MolliePay::InvalidAmount) { MolliePay.mollie_amount(BigDecimal(amount)) }
    end
  end

  test "a stored amount with too many digits is invalid, not rounded" do
    payment = mollie_pay_payments(:acme_first)

    payment.amount = BigDecimal("10.12345678")
    assert payment.valid?

    payment.amount = BigDecimal("10.123456789")
    assert_not payment.valid?
  end
end
