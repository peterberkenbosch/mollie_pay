require "test_helper"

module MolliePay
  class SubscriptionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "active? reflects status" do
      assert mollie_pay_subscriptions(:acme_monthly).active?
    end

    test "active scope returns active subscriptions" do
      assert_includes Subscription.active, mollie_pay_subscriptions(:acme_monthly)
    end

    test "requires valid status" do
      sub = mollie_pay_subscriptions(:acme_monthly)
      sub.status = "nonsense"
      assert_not sub.valid?
    end

    test "requires positive amount" do
      sub = mollie_pay_subscriptions(:acme_monthly)
      sub.amount = 0
      assert_not sub.valid?
    end

    test "record_from_mollie creates subscription from mollie object" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      mollie_sub = stub_mollie_subscription(
        id:          "sub_new456",
        status:      "active",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "30.00",
        amount_currency: "EUR"
      )

      subscription = Subscription.record_from_mollie(mollie_sub)

      assert_equal "sub_new456", subscription.mollie_id
      assert_equal "active", subscription.status
      assert_equal BigDecimal("30.00"), subscription.amount
      assert_equal "1 month", subscription.interval
    end

    test "record_from_mollie updates existing subscription" do
      existing = mollie_pay_subscriptions(:acme_monthly)

      mollie_sub = stub_mollie_subscription(
        id:          existing.mollie_id,
        status:      "canceled",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "25.00",
        amount_currency: "EUR"
      )

      Subscription.record_from_mollie(mollie_sub)

      assert_equal "canceled", existing.reload.status
      assert_not_nil existing.canceled_at
    end

    test "record_from_mollie calls canceled hook on billable" do
      existing = mollie_pay_subscriptions(:acme_monthly)

      mollie_sub = stub_mollie_subscription(
        id:          existing.mollie_id,
        status:      "canceled",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "25.00",
        amount_currency: "EUR"
      )

      Subscription.record_from_mollie(mollie_sub)

      assert_equal "canceled", existing.reload.status
      assert_enqueued_with job: NotifyBillableJob, args: [ existing.customer.owner, :on_mollie_subscription_canceled, existing ]
    end

    test "notify_billable enqueues the suspended and completed hooks" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      owner = subscription.customer.owner

      { "suspended" => :on_mollie_subscription_suspended, "completed" => :on_mollie_subscription_completed }.each do |status, hook|
        subscription.status = status
        subscription.notify_billable

        assert_enqueued_with job: NotifyBillableJob, args: [ owner, hook, subscription ]
      end
    end

    test "name validates presence" do
      sub = mollie_pay_subscriptions(:acme_monthly)
      sub.name = ""
      assert_not sub.valid?
      assert_includes sub.errors[:name], "can't be blank"
    end

    test "named scope filters by name" do
      assert_includes Subscription.named("default"), mollie_pay_subscriptions(:acme_monthly)
      assert_includes Subscription.named("analytics_addon"), mollie_pay_subscriptions(:acme_addon)
      assert_empty Subscription.named("nonexistent")
    end

    test "record_from_mollie preserves existing name" do
      existing = mollie_pay_subscriptions(:acme_monthly)
      assert_equal "default", existing.name

      mollie_sub = stub_mollie_subscription(
        id:          existing.mollie_id,
        status:      "active",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "25.00",
        amount_currency: "EUR"
      )

      Subscription.record_from_mollie(mollie_sub)

      assert_equal "default", existing.reload.name
    end

    test "record_from_mollie reads name from metadata for new records" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      mollie_sub = stub_mollie_subscription(
        id:          "sub_from_webhook",
        status:      "active",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "30.00",
        amount_currency: "EUR",
        metadata:    { "mollie_pay_name" => "premium" }
      )

      subscription = Subscription.record_from_mollie(mollie_sub)

      assert_equal "premium", subscription.name
    end

    test "record_from_mollie defaults name to 'default' without metadata" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      mollie_sub = stub_mollie_subscription(
        id:          "sub_no_meta",
        status:      "active",
        customer_id: mollie_pay_customers(:acme).mollie_id,
        interval:    "1 month",
        amount_value: "20.00",
        amount_currency: "EUR"
      )

      subscription = Subscription.record_from_mollie(mollie_sub)

      assert_equal "default", subscription.name
    end

    test "mollie_record fetches the subscription through its customer" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      customer_id = subscription.customer.mollie_id
      stub_request(:get, "#{MOLLIE_API_BASE}/customers/#{customer_id}/subscriptions/#{subscription.mollie_id}")
        .to_return(status: 200, body: mollie_fixture("subscription", id: subscription.mollie_id, customer_id: customer_id),
                   headers: { "Content-Type" => "application/hal+json" })

      assert_equal Date.new(2026, 4, 15), subscription.mollie_record.next_payment_date
    end

    private

      def stub_mollie_subscription(id:, status:, customer_id:, interval:, amount_value:, amount_currency:, metadata: nil)
        amount = OpenStruct.new(value: amount_value, currency: amount_currency)
        OpenStruct.new(
          id:          id,
          status:      status,
          customer_id: customer_id,
          interval:    interval,
          amount:      amount,
          metadata:    metadata
        )
      end
  end
end
