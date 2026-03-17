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

    test "record_from_mollie links recurring payment to subscription" do
      customer     = mollie_pay_customers(:acme)
      subscription = mollie_pay_subscriptions(:acme_monthly)

      mollie_payment = stub_mollie_payment(
        id:              "tr_recurring_new",
        status:          "paid",
        customer_id:     customer.mollie_id,
        sequence_type:   "recurring",
        amount_value:    "25.00",
        amount_currency: "EUR",
        subscription_id: subscription.mollie_id
      )

      payment = Payment.record_from_mollie(mollie_payment)
      assert_equal subscription, payment.subscription
    end

    test "record_from_mollie ignores subscription_id when subscription not found locally" do
      customer = mollie_pay_customers(:acme)

      mollie_payment = stub_mollie_payment(
        id:              "tr_orphan",
        status:          "paid",
        customer_id:     customer.mollie_id,
        sequence_type:   "recurring",
        amount_value:    "25.00",
        amount_currency: "EUR",
        subscription_id: "sub_nonexistent"
      )

      payment = Payment.record_from_mollie(mollie_payment)
      assert_nil payment.subscription
    end

    test "record_from_mollie sets authorized_at on first authorized observation" do
      customer = mollie_pay_customers(:acme)

      mollie_payment = stub_mollie_payment(
        id:            "tr_auth1",
        status:        "authorized",
        customer_id:   customer.mollie_id,
        sequence_type: "oneoff",
        amount_value:  "50.00",
        amount_currency: "EUR"
      )

      payment = Payment.record_from_mollie(mollie_payment)
      assert_not_nil payment.authorized_at

      original_authorized_at = payment.authorized_at
      Payment.record_from_mollie(mollie_payment)
      assert_equal original_authorized_at, payment.reload.authorized_at
    end

    test "record_from_mollie populates amount tracking columns" do
      customer = mollie_pay_customers(:acme)

      mollie_payment = stub_mollie_payment(
        id:              "tr_tracked",
        status:          "paid",
        customer_id:     customer.mollie_id,
        sequence_type:   "oneoff",
        amount_value:    "100.00",
        amount_currency: "EUR",
        amount_refunded: OpenStruct.new(value: "10.00", currency: "EUR"),
        amount_remaining: OpenStruct.new(value: "90.00", currency: "EUR"),
        amount_captured: OpenStruct.new(value: "100.00", currency: "EUR"),
        amount_charged_back: OpenStruct.new(value: "5.00", currency: "EUR")
      )

      payment = Payment.record_from_mollie(mollie_payment)

      assert_equal 1000, payment.amount_refunded
      assert_equal 9000, payment.amount_remaining
      assert_equal 10000, payment.amount_captured
      assert_equal 500, payment.amount_charged_back
    end

    test "record_from_mollie preserves amount tracking when Mollie omits fields" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_payments(:acme_oneoff)

      mollie_payment = stub_mollie_payment(
        id:              existing.mollie_id,
        status:          "paid",
        customer_id:     customer.mollie_id,
        sequence_type:   "oneoff",
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      Payment.record_from_mollie(mollie_payment)

      assert_equal 0, existing.reload.amount_refunded
      assert_nil existing.amount_remaining
      assert_equal 0, existing.amount_captured
      assert_equal 0, existing.amount_charged_back
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

    def stub_mollie_payment(id:, status:, customer_id:, sequence_type:, amount_value:, amount_currency:,
                            subscription_id: nil, amount_refunded: nil, amount_remaining: nil,
                            amount_captured: nil, amount_charged_back: nil)
      amount = OpenStruct.new(value: amount_value, currency: amount_currency)
      OpenStruct.new(
        id:                  id,
        status:              status,
        customer_id:         customer_id,
        sequence_type:       sequence_type,
        amount:              amount,
        mandate_id:          nil,
        subscription_id:     subscription_id,
        amount_refunded:     amount_refunded,
        amount_remaining:    amount_remaining,
        amount_captured:     amount_captured,
        amount_charged_back: amount_charged_back
      )
    end
  end
end
