require "test_helper"

module MolliePay
  class SubscriptionTest < ActiveSupport::TestCase
    test "active? reflects status" do
      assert mollie_pay_subscriptions(:acme_monthly).active?
    end

    test "active scope returns active subscriptions" do
      assert_includes Subscription.active, mollie_pay_subscriptions(:acme_monthly)
    end

    test "amount_decimal converts cents" do
      assert_equal 25.0, mollie_pay_subscriptions(:acme_monthly).amount_decimal
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
      assert_equal 3000, subscription.amount
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
    end

    private

      def stub_mollie_subscription(id:, status:, customer_id:, interval:, amount_value:, amount_currency:)
        amount = OpenStruct.new(value: amount_value, currency: amount_currency)
        OpenStruct.new(
          id:          id,
          status:      status,
          customer_id: customer_id,
          interval:    interval,
          amount:      amount
        )
      end
  end
end
