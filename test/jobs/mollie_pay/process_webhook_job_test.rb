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
  end
end
