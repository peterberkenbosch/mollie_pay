require "test_helper"

module MolliePay
  class WebhookEventTest < ActiveSupport::TestCase
    test "processed? returns true when processed_at is set" do
      assert mollie_pay_webhook_events(:payment_event).processed?
    end

    test "failed? returns true when failed_at is set" do
      assert mollie_pay_webhook_events(:failed_event).failed?
    end

    test "pending scope excludes processed and failed events" do
      pending = WebhookEvent.pending
      assert_includes pending, mollie_pay_webhook_events(:pending_event)
      assert_not_includes pending, mollie_pay_webhook_events(:payment_event)
      assert_not_includes pending, mollie_pay_webhook_events(:failed_event)
    end

    test "process! marks event processed" do
      event = mollie_pay_webhook_events(:pending_event)

      Mollie::Payment.stub(:get, stub_mollie_payment_object) do
        Payment.stub(:record_from_mollie, mollie_pay_payments(:acme_oneoff)) do
          event.process!
        end
      end

      assert event.processed?
      assert_not_nil event.processed_at
    end

    test "process! marks event failed and re-raises on error" do
      event = WebhookEvent.create!(mollie_id: "tr_bad123")

      Mollie::Payment.stub(:get, ->(_) { raise Mollie::Exception, "API down" }) do
        assert_raises(Mollie::Exception) { event.process! }
      end

      assert event.reload.failed?
      assert_equal "API down", event.error
    end

    private

      def stub_mollie_payment_object
        amount = OpenStruct.new(value: "10.00", currency: "EUR")
        OpenStruct.new(
          id:            "tr_pending123",
          status:        "paid",
          customer_id:   mollie_pay_customers(:acme).mollie_id,
          sequence_type: "oneoff",
          amount:        amount,
          mandate_id:    nil
        )
      end
  end
end
