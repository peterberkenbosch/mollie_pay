require "test_helper"

module MolliePay
  class PaymentTest < ActiveSupport::TestCase
    test "paid? reflects status" do
      assert mollie_pay_payments(:acme_first).paid?
      assert_not mollie_pay_payments(:acme_oneoff).paid?
    end

    test "first_payment? reflects sequence_type" do
      assert mollie_pay_payments(:acme_first).first_payment?
      assert_not mollie_pay_payments(:acme_recurring).first_payment?
    end

    test "recurring? reflects sequence_type" do
      assert mollie_pay_payments(:acme_recurring).recurring?
      assert_not mollie_pay_payments(:acme_first).recurring?
    end

    test "amount_decimal converts cents" do
      assert_equal 10.0, mollie_pay_payments(:acme_first).amount_decimal
    end

    test "mollie_amount returns correct hash" do
      expected = { currency: "EUR", value: "10.00" }
      assert_equal expected, mollie_pay_payments(:acme_first).mollie_amount
    end

    test "paid scope returns only paid payments" do
      paid = Payment.paid
      assert_includes paid, mollie_pay_payments(:acme_first)
      assert_not_includes paid, mollie_pay_payments(:acme_oneoff)
    end

    test "record_from_mollie creates payment from mollie object" do
      customer = mollie_pay_customers(:acme)

      mollie_payment = stub_mollie_payment(
        id:            "tr_new123",
        status:        "open",
        customer_id:   customer.mollie_id,
        sequence_type: "oneoff",
        amount_value:  "25.00",
        amount_currency: "EUR"
      )

      payment = Payment.record_from_mollie(mollie_payment)

      assert_equal "tr_new123", payment.mollie_id
      assert_equal "open", payment.status
      assert_equal 2500, payment.amount
    end

    test "record_from_mollie updates existing payment" do
      customer  = mollie_pay_customers(:acme)
      existing  = mollie_pay_payments(:acme_oneoff)

      mollie_payment = stub_mollie_payment(
        id:              existing.mollie_id,
        status:          "paid",
        customer_id:     customer.mollie_id,
        sequence_type:   "oneoff",
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      Payment.record_from_mollie(mollie_payment)
      assert_equal "paid", existing.reload.status
    end

    test "record_from_mollie does not overwrite paid_at on duplicate webhook" do
      existing = mollie_pay_payments(:acme_first)
      original_paid_at = existing.paid_at

      mollie_payment = stub_mollie_payment(
        id:              existing.mollie_id,
        status:          "paid",
        customer_id:     existing.customer.mollie_id,
        sequence_type:   "first",
        amount_value:    "10.00",
        amount_currency: "EUR"
      )

      Payment.record_from_mollie(mollie_payment)
      assert_equal original_paid_at, existing.reload.paid_at
    end

    test "record_from_mollie skips notify_billable when status unchanged" do
      existing = mollie_pay_payments(:acme_first)
      assert_equal "paid", existing.status

      mollie_payment = stub_mollie_payment(
        id:              existing.mollie_id,
        status:          "paid",
        customer_id:     existing.customer.mollie_id,
        sequence_type:   "first",
        amount_value:    "10.00",
        amount_currency: "EUR"
      )

      # If notify_billable fires, it would call Mandate.record_from_mollie_payment
      # which calls payment.mollie_record (API call). Since status doesn't change,
      # it should be skipped entirely.
      payment = Payment.record_from_mollie(mollie_payment)
      assert_equal "paid", payment.status
    end

    private

    def stub_mollie_payment(id:, status:, customer_id:, sequence_type:, amount_value:, amount_currency:)
      amount = OpenStruct.new(value: amount_value, currency: amount_currency)
      OpenStruct.new(
        id:            id,
        status:        status,
        customer_id:   customer_id,
        sequence_type: sequence_type,
        amount:        amount,
        mandate_id:    nil
      )
    end
  end
end
