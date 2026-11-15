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
    [ "Infinity", "NaN", "1e1000000", "100000000.01", "0.12345" ].each do |amount|
      assert_raises(MolliePay::InvalidAmount) { MolliePay.mollie_amount(BigDecimal(amount)) }
    end
  end

  test "a stored amount with a fifth decimal is invalid, not rounded" do
    payment = mollie_pay_payments(:acme_first)

    payment.amount = BigDecimal("10.1234")
    assert payment.valid?

    payment.amount = BigDecimal("10.12345")
    assert_not payment.valid?
  end

  test "money round-trips through the decimal column as an exact BigDecimal" do
    payment = mollie_pay_payments(:acme_first)
    payment.update!(amount: BigDecimal("19.9995"))

    assert_instance_of BigDecimal, payment.reload.amount
    assert_equal BigDecimal("19.9995"), payment.amount
    assert payment.valid?
  end
end
