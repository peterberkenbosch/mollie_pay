require "test_helper"

module MolliePay
  class RefundTest < ActiveSupport::TestCase
    test "refunded? reflects status" do
      refund = mollie_pay_refunds(:acme_refund)
      assert_not refund.refunded?

      refund.status = "refunded"
      assert refund.refunded?
    end

    test "requires valid status" do
      refund = mollie_pay_refunds(:acme_refund)
      refund.status = "nonsense"
      assert_not refund.valid?
    end

    test "requires positive amount" do
      refund = mollie_pay_refunds(:acme_refund)
      refund.amount = 0
      assert_not refund.valid?
    end

    test "refunded scope returns refunded refunds" do
      refund = mollie_pay_refunds(:acme_refund)
      assert_not_includes Refund.refunded, refund

      refund.update!(status: "refunded", refunded_at: Time.current)
      assert_includes Refund.refunded, refund
    end

    test "record_from_mollie creates refund from mollie object" do
      payment = mollie_pay_payments(:acme_oneoff)

      mollie_refund = stub_mollie_refund(
        id:              "re_new789",
        status:          "pending",
        payment_id:      payment.mollie_id,
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      refund = Refund.record_from_mollie(mollie_refund)

      assert_equal "re_new789", refund.mollie_id
      assert_equal "pending", refund.status
      assert_equal 7500, refund.amount
    end

    test "record_from_mollie updates existing refund" do
      existing = mollie_pay_refunds(:acme_refund)

      mollie_refund = stub_mollie_refund(
        id:              existing.mollie_id,
        status:          "refunded",
        payment_id:      existing.payment.mollie_id,
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      Refund.record_from_mollie(mollie_refund)

      assert_equal "refunded", existing.reload.status
      assert_not_nil existing.refunded_at
    end

    test "record_from_mollie calls refund hook on status transition" do
      existing = mollie_pay_refunds(:acme_refund)

      mollie_refund = stub_mollie_refund(
        id:              existing.mollie_id,
        status:          "refunded",
        payment_id:      existing.payment.mollie_id,
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      Refund.record_from_mollie(mollie_refund)

      assert_equal "refunded", existing.reload.status
      assert_not_nil existing.refunded_at
    end

    test "record_from_mollie does not overwrite refunded_at on duplicate webhook" do
      existing = mollie_pay_refunds(:acme_refund)
      existing.update!(status: "refunded", refunded_at: 1.day.ago)
      original_refunded_at = existing.refunded_at

      mollie_refund = stub_mollie_refund(
        id:              existing.mollie_id,
        status:          "refunded",
        payment_id:      existing.payment.mollie_id,
        amount_value:    "75.00",
        amount_currency: "EUR"
      )

      Refund.record_from_mollie(mollie_refund)

      assert_equal original_refunded_at, existing.reload.refunded_at
    end

    private

      def stub_mollie_refund(id:, status:, payment_id:, amount_value:, amount_currency:)
        amount = OpenStruct.new(value: amount_value, currency: amount_currency)
        OpenStruct.new(
          id:         id,
          status:     status,
          payment_id: payment_id,
          amount:     amount
        )
      end
  end
end
