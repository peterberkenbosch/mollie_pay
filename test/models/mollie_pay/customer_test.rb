require "test_helper"

module MolliePay
  class CustomerTest < ActiveSupport::TestCase
    test "requires mollie_id" do
      customer = Customer.new(owner: nil)
      assert_not customer.valid?
      assert_includes customer.errors[:mollie_id], "can't be blank"
    end

    test "mollie_id must be unique" do
      existing = mollie_pay_customers(:acme)
      duplicate = Customer.new(mollie_id: existing.mollie_id)
      assert_not duplicate.valid?
    end

    test "subscribed? returns true when active subscription exists" do
      assert mollie_pay_customers(:acme).subscribed?
    end

    test "mandated? returns true when valid mandate exists" do
      assert mollie_pay_customers(:acme).mandated?
    end

    test "active_subscription returns an active subscription" do
      sub = mollie_pay_customers(:acme).active_subscription
      assert sub.active?
      assert_includes [ mollie_pay_subscriptions(:acme_monthly), mollie_pay_subscriptions(:acme_addon) ], sub
    end
  end
end
