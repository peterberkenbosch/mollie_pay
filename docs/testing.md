# Testing

MolliePay ships test helpers for Minitest that stub all Mollie API calls. Add
to your `test/test_helper.rb`:

```ruby
require "mollie_pay/test_helper"

class ActiveSupport::TestCase
  include MolliePay::TestHelper
end
```

This gives you stub helpers and fake response builders in all your tests.

## Stub helpers

Each helper stubs a Mollie API call and runs your block:

```ruby
class OrganizationTest < ActiveSupport::TestCase
  test "one-off payment" do
    stub_mollie_payment_create do
      payment = @org.mollie_pay_once(amount: 5000, description: "Test")
      assert_equal "open", payment.status
      assert payment.checkout_url.present?
    end
  end

  test "first payment with new customer" do
    stub_mollie_customer_and_payment_create do
      payment = new_org.mollie_pay_first(amount: 1000, description: "Setup")
      assert new_org.reload.mollie_customer.present?
    end
  end

  test "subscribe" do
    stub_mollie_subscription_create do
      subscription = @org.mollie_subscribe(
        amount: 2500, interval: "1 month", description: "Monthly"
      )
      assert_equal "active", subscription.status
    end
  end

  test "cancel subscription" do
    stub_mollie_subscription_cancel do
      @org.mollie_cancel_subscription
    end
  end

  test "refund" do
    stub_mollie_refund_create do
      refund = @org.mollie_refund(payment)
      assert_equal "queued", refund.status
    end
  end
end
```

All stubs accept keyword overrides to control the Mollie response:

```ruby
stub_mollie_payment_create(id: "tr_custom123", status: "paid") do
  # ...
end

stub_mollie_customer_and_payment_create(
  customer_overrides: { id: "cst_specific" },
  payment_overrides:  { id: "tr_specific", status: "open" }
) do
  # ...
end
```

## Fake response builders

Build individual Mollie response objects when you need more control:

```ruby
response = fake_mollie_payment(id: "tr_test123", status: "paid")
response = fake_mollie_customer(id: "cst_test123")
response = fake_mollie_subscription(id: "sub_test123", status: "active")
response = fake_mollie_refund(id: "re_test123", status: "queued")
```

All IDs default to random values (`tr_test<hex>`, etc.) when not specified.

## Available helpers

| Helper | Stubs | Default response |
|---|---|---|
| `stub_mollie_payment_create` | `Mollie::Payment.create` | `status: "open"`, random ID and checkout URL |
| `stub_mollie_customer_and_payment_create` | `Mollie::Customer.create` + `Mollie::Payment.create` | Both with random IDs |
| `stub_mollie_subscription_create` | `Mollie::Customer::Subscription.create` | `status: "active"`, random ID |
| `stub_mollie_subscription_cancel` | `Mollie::Customer::Subscription.cancel` | Returns nil |
| `stub_mollie_refund_create` | `Mollie::Refund.create` | `status: "queued"`, random ID |

## WebMock-based API stubs

For integration tests that exercise the full Mollie SDK pipeline (JSON parsing,
object construction, HTTP handling), use the `webmock_mollie_*` helpers. These
stub the actual HTTP endpoints with realistic Mollie API v2 HAL+JSON responses.

```ruby
class OrganizationIntegrationTest < ActiveSupport::TestCase
  test "payment creation through full SDK pipeline" do
    webmock_mollie_payment_create do
      payment = @org.mollie_pay_once(amount: 5000, description: "Test")
      assert_equal "tr_test1234AB", payment.mollie_id
    end
  end

  test "subscription" do
    webmock_mollie_subscription_create do
      subscription = @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")
      assert_equal "sub_test1234AB", subscription.mollie_id
    end
  end

  test "webhook payment fetch" do
    webmock_mollie_payment_get("tr_abc123", status: "paid", customer_id: "cst_xyz") do
      mollie_payment = Mollie::Payment.get("tr_abc123")
      assert_equal "paid", mollie_payment.status
    end
  end
end
```

All WebMock helpers accept keyword overrides that merge into the JSON fixture:

```ruby
webmock_mollie_payment_create(id: "tr_custom", status: "paid", amount_value: "50.00") do
  # ...
end
```

| Helper | Stubs | Endpoint |
|---|---|---|
| `webmock_mollie_payment_create` | `POST /v2/payments` | Full payment JSON with checkout link |
| `webmock_mollie_customer_and_payment_create` | `POST /v2/customers` + `POST /v2/payments` | Both resources |
| `webmock_mollie_subscription_create` | `POST /v2/subscriptions` | Active subscription JSON |
| `webmock_mollie_subscription_cancel` | `DELETE /v2/subscriptions/:id` | 204 No Content |
| `webmock_mollie_refund_create` | `POST /v2/refunds` | Queued refund JSON |
| `webmock_mollie_payment_get` | `GET /v2/payments/:id` | Payment JSON (for webhook tests) |

**When to use which:** Method-level stubs (`stub_mollie_*`) are faster and
simpler — use them for unit tests. WebMock stubs (`webmock_mollie_*`) exercise
the full SDK including JSON parsing — use them for integration tests.
