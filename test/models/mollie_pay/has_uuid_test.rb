require "test_helper"

module MolliePay
  class HasUuidTest < ActiveSupport::TestCase
    test "assigns a UUIDv7 string id on create when none is given" do
      customer = Customer.create!(owner: Organization.create!(name: "New Co"), mollie_id: "cst_uuid_new")

      assert_kind_of String, customer.id
      assert_equal 36, customer.id.length
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\z/, customer.id)
    end

    test "keeps an explicitly provided id" do
      explicit = SecureRandom.uuid_v7
      customer = Customer.create!(id: explicit, owner: Organization.create!(name: "Explicit Co"), mollie_id: "cst_uuid_explicit")

      assert_equal explicit, customer.id
    end

    test "assigns time-ordered ids" do
      first  = Customer.create!(owner: Organization.create!(name: "A Co"), mollie_id: "cst_uuid_a")
      second = Customer.create!(owner: Organization.create!(name: "B Co"), mollie_id: "cst_uuid_b")

      assert first.id < second.id, "UUIDv7 ids should sort in creation order"
    end
  end
end
