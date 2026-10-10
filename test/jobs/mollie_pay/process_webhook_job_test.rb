require "test_helper"

module MolliePay
  class ProcessWebhookJobTest < ActiveJob::TestCase
    test "processes payment webhook" do
      customer = mollie_pay_customers(:acme)

      webmock_mollie_payment_get("tr_newpayment", status: "paid", customer_id: customer.mollie_id) do
        ProcessWebhookJob.perform_now("tr_newpayment")
      end

      assert MolliePay::Payment.find_by(mollie_id: "tr_newpayment")
    end

    # === Billink (manual capture) lifecycle ===

    test "billink webhook moves an open payment to authorized once and fires the hook once" do
      payment = mollie_pay_payments(:acme_oneoff)

      with_organization_hook(:on_mollie_payment_authorized) do |calls|
        2.times do
          deliver_billink_webhook(payment, status: "authorized")
        end

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "authorized", payment.status
      assert_not_nil payment.authorized_at
    end

    test "billink webhook keeps authorized_at unchanged on a repeated authorized webhook" do
      payment = mollie_pay_payments(:acme_oneoff)

      deliver_billink_webhook(payment, status: "authorized")
      first_authorized_at = payment.reload.authorized_at

      travel 1.hour do
        deliver_billink_webhook(payment, status: "authorized")
      end

      assert_equal first_authorized_at, payment.reload.authorized_at
    end

    test "billink webhook moves an authorized payment to paid after capture and fires the paid hook once" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_paid) do |calls|
        deliver_billink_webhook(payment, status: "paid")

        assert_equal 1, calls.size
        assert_equal payment, calls.first
      end

      payment.reload
      assert_equal "paid", payment.status
      assert_not_nil payment.paid_at
      assert_not_nil payment.authorized_at
    end

    test "billink webhook moves an authorized payment to canceled after release and fires the canceled hook" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_canceled) do |calls|
        deliver_billink_webhook(payment, status: "canceled")

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "canceled", payment.status
      assert_not_nil payment.canceled_at
    end

    test "billink webhook moves an authorized payment to expired and fires the expired hook" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_expired) do |calls|
        deliver_billink_webhook(payment, status: "expired")

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "expired", payment.status
      assert_not_nil payment.expired_at
    end

    test "processes subscription webhook" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      response = OpenStruct.new(
        id: subscription.mollie_id, status: "canceled",
        customer_id: subscription.customer.mollie_id,
        amount: OpenStruct.new(value: "25.00", currency: "EUR"),
        interval: "1 month", metadata: nil
      )

      Mollie::Subscription.stub(:get, response) do
        ProcessWebhookJob.perform_now(subscription.mollie_id)
      end

      assert_equal "canceled", subscription.reload.status
    end

    test "processes refund webhook" do
      refund = mollie_pay_refunds(:acme_refund)
      response = OpenStruct.new(
        id: refund.mollie_id, status: "refunded",
        payment_id: refund.payment.mollie_id,
        amount: OpenStruct.new(value: "75.00", currency: "EUR")
      )

      Mollie::Refund.stub(:get, response) do
        ProcessWebhookJob.perform_now(refund.mollie_id)
      end

      assert_equal "refunded", refund.reload.status
    end

    test "processes settlement webhook via ActiveSupport::Notifications" do
      settlement = OpenStruct.new(
        id: "stl_test123", status: "paidout",
        amount: OpenStruct.new(value: "100.00", currency: "EUR")
      )

      received = nil
      ActiveSupport::Notifications.subscribe("mollie_pay.settlement_received") do |*, payload|
        received = payload[:settlement]
      end

      Mollie::Settlement.stub(:get, settlement) do
        ProcessWebhookJob.perform_now("stl_test123")
      end

      assert_equal "stl_test123", received.id
      assert_equal "paidout", received.status
    ensure
      ActiveSupport::Notifications.unsubscribe("mollie_pay.settlement_received")
    end

    test "logs unknown webhook prefix" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("ord_unknown123")
      end
    end

    test "retries on failure" do
      Mollie::Payment.stub(:get, ->(_) { raise StandardError, "Mollie down" }) do
        assert_enqueued_with(job: ProcessWebhookJob) do
          ProcessWebhookJob.perform_now("tr_test123")
        end
      end
    end

    test "discards when Mollie resource not found" do
      Mollie::Payment.stub(:get, ->(_) { raise Mollie::ResourceNotFoundError.new({}) }) do
        assert_nothing_raised do
          ProcessWebhookJob.perform_now("tr_nonexistent")
        end
      end
    end

    test "discards when local subscription not found" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("sub_nonexistent")
      end
    end

    test "discards when local refund not found" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("re_nonexistent")
      end
    end

    private

      def deliver_billink_webhook(payment, status:)
        webmock_mollie_payment_get(payment.mollie_id, fixture: "payment_billink", status: status, customer_id: payment.customer.mollie_id) do
          ProcessWebhookJob.perform_now(payment.mollie_id)
        end
      end

      # Payment.record_from_mollie reloads the owner, so a singleton method on
      # a test-local instance is never reached. Define the hook on the class
      # for the duration of the block and collect the payments it received.
      def with_organization_hook(hook_name)
        calls = []
        Organization.define_method(hook_name) { |payment| calls << payment }
        yield calls
      ensure
        Organization.remove_method(hook_name)
      end
  end
end
