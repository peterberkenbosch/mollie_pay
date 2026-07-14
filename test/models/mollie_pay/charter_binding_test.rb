require "test_helper"

module MolliePay
  # Confirms MolliePay::Billable matches the engine-family charter's unified
  # polymorphic identity concern: the host model is the binding point, and the
  # polymorphic owner resolves with string (UUIDv7) ids.
  class CharterBindingTest < ActiveSupport::TestCase
    test "the polymorphic owner resolves via the host's string PK" do
      org      = organizations(:acme)
      customer = mollie_pay_customers(:acme)

      assert_kind_of String, customer.owner_id
      assert_equal org.id, customer.owner_id
      assert_equal "Organization", customer.owner_type
      assert_equal org, customer.owner
    end

    test "a host including Billable binds a customer with string ids and exposes the associations" do
      org      = Organization.create!(name: "Binding Co")
      customer = Customer.create!(owner: org, mollie_id: "cst_binding")

      assert_kind_of String, org.id
      assert_kind_of String, customer.id
      assert_equal customer, org.mollie_customer
      assert_respond_to org, :mollie_subscriptions
      assert_respond_to org, :mollie_payments
      assert_respond_to org, :mollie_mandates
      assert_respond_to org, :mollie_sales_invoices
    end
  end
end
