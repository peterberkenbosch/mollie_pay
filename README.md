# MolliePay

A mountable Rails engine for Mollie payments in SaaS applications. Handles
customers, mandates, subscriptions, one-off payments, refunds and webhooks.
You write the business logic; MolliePay handles the Mollie plumbing.

Rails 8+, Mollie-native.

## Philosophy

- **Headless.** No views, no UI opinions. One mounted webhook endpoint, nothing else.
- **Lean data model.** Only business-critical fields are stored locally. Everything else is fetched from Mollie on demand via `record.mollie_record`.
- **Hooks, not events.** Override plain Ruby methods in your model. No event bus, no pub/sub, no callbacks to register.
- **Boring Rails.** Models do the work. No service objects, no form objects, no interactors.
- **Idempotent.** Hooks fire only on actual status transitions. Duplicate webhooks from Mollie are handled safely.
- **Cents, not floats.** All amounts are stored as integers (cents). Conversion happens only at the Mollie API boundary.

## Requirements

- Ruby 3.2+
- Rails 8.0+
- Active Job (any queue adapter)
- A [Mollie](https://my.mollie.com/dashboard/signup/7878281?lang=nl) account and API key

## Installation

Add to your Gemfile:

```ruby
gem "mollie_pay"
```

Install:

```sh
bundle install
bin/rails generate mollie_pay:install
```

This creates the initializer, copies migrations, and runs them.

Mount the engine in `config/routes.rb`:

```ruby
mount MolliePay::Engine => "/mollie_pay"
```

The generated initializer at `config/initializers/mollie_pay.rb`:

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"]       # e.g. "https://yourapp.com"
  config.default_redirect_path = "/payments/:id"           # :id is replaced with the local payment ID
  config.currency              = "EUR"                    # default
end
```

The engine validates that `api_key` and `host` are set, then configures the
Mollie Ruby SDK automatically on boot. A missing key raises
`MolliePay::ConfigurationError` at startup — not deep in a background job.

The webhook URL is derived automatically from `host` and the engine's mount
path (`/mollie_pay/webhooks`). No manual webhook URL configuration needed.

## Setup

Include `MolliePay::Billable` in the model that represents your paying entity
(organization, team, user, etc.):

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable
end
```

That's it. Your model now has the full Mollie billing API available.

MolliePay creates a `MolliePay::Customer` record linked to your model via a
polymorphic `has_one` association. The Mollie customer is created lazily on the
first payment or subscription call.

If your model responds to `name` and `email`, those values are sent to Mollie
when creating the customer.

## Usage

### Typical SaaS flow

Mollie recurring billing requires a **mandate** before a subscription can be
created. The standard flow is:

**1. First payment — establishes the mandate**

```ruby
payment = current_organization.mollie_pay_first(
  amount:       1000, # 10.00 in cents
  description:  "Activation fee",
  redirect_url: payment_url(payment), # optional if default_redirect_path is configured
  method:       "ideal" # optional — omit to let Mollie show all enabled methods
)

redirect_to payment.checkout_url
```

After creating the payment, MolliePay stores the Mollie checkout URL on the
payment record. Redirect the customer to `payment.checkout_url` — this is the
Mollie-hosted payment page where they complete payment via iDEAL, credit card or
another method. Mollie fires a webhook. MolliePay stores the mandate
automatically.

When the customer finishes (or abandons) payment, Mollie redirects them back to
the `redirect_url` you provided (or the `default_redirect_path` with the payment
ID interpolated). If you configured `default_redirect_path`, you can omit
`redirect_url:` from the call.

**2. Subscribe — requires a valid mandate**

```ruby
current_organization.mollie_subscribe(
  amount:      2500,        # 25.00 in cents
  interval:    "1 month",   # Mollie interval format
  description: "Monthly plan"
)
```

Raises `MolliePay::MandateRequired` if no valid mandate is on file.

**3. One-off payment — no mandate required**

```ruby
payment = current_organization.mollie_pay_once(
  amount:       7500,
  description:  "Extra service",
  redirect_url: payment_url(payment), # optional if default_redirect_path is configured
  method:       "creditcard" # optional — omit to let Mollie show all enabled methods
)

redirect_to payment.checkout_url
```

**4. Cancel subscription**

```ruby
current_organization.mollie_cancel_subscription
```

Raises `MolliePay::SubscriptionNotFound` if no active subscription exists.

**5. Refund**

```ruby
current_organization.mollie_refund(payment)              # full refund
current_organization.mollie_refund(payment, amount: 500) # partial — 5.00
```

Multiple partial refunds against the same payment are supported. Each creates
a separate `MolliePay::Refund` record.

### Querying billing state

```ruby
org.mollie_subscribed?      # => true/false
org.mollie_mandated?        # => true/false
org.mollie_subscription     # => MolliePay::Subscription or nil
org.mollie_mandate          # => MolliePay::Mandate or nil
org.mollie_payments         # => ActiveRecord::Relation
```

### Fetching live Mollie data

Every local record exposes `mollie_record`, which fetches the full object from
the Mollie API on demand:

```ruby
subscription.mollie_record.next_payment_date
mandate.mollie_record.details
customer.mollie_record.locale
```

This is a live API call — don't use it in loops or list views. Use it for
display in detail pages or for accessing fields that aren't stored locally.

### Amounts

All amounts in MolliePay are **integers representing cents**. This avoids
floating-point precision issues.

```ruby
payment.amount          # => 2500 (cents)
payment.amount_decimal  # => 25.0 (for display)
payment.mollie_amount   # => { currency: "EUR", value: "25.00" } (Mollie format)
```

The same `amount_decimal` and `mollie_amount` methods are available on
`Subscription` and `Refund`.

## Webhooks

### Endpoint

Point your Mollie dashboard webhook URL to:

```
POST https://yourapp.com/mollie_pay/webhooks
```

### How it works

```
POST /mollie_pay/webhooks              (from Mollie)
  → validate mollie_id format           (reject junk IDs with 422)
  → skip if pending event already exists (deduplicate retries)
  → WebhookEvent.create!                (log the inbound ID)
  → ProcessWebhookJob.perform_later     (enqueue for async processing)
  → head :ok                            (respond immediately)

ProcessWebhookJob:
  → skip if event already processed
  → event.process!
  → fetch full object from Mollie API
  → upsert local record via record_from_mollie
  → fire on_mollie_* hook on billable (only on status transitions)
  → mark event processed
```

MolliePay responds immediately with `200 OK`, then processes asynchronously via
Active Job. Duplicate webhooks from Mollie are deduplicated at the controller
level — if a pending event for the same ID already exists, no new job is
enqueued. On failure, the job retries with polynomial backoff (up to 5
attempts). Resources not found on Mollie (404) are discarded, not retried.

### Verification

No signature verification is needed. Mollie's webhook pattern sends only an
`id` parameter, which MolliePay validates against the format
`(tr|sub|re)_[a-zA-Z0-9]+` and then fetches directly from the Mollie API.
The API key is the verification — only your key can fetch your objects.

### Idempotency

Hooks fire **only on actual status transitions**. If Mollie sends the same
webhook multiple times (which it does routinely), the local record is updated
but hooks are not re-triggered. This means your `on_mollie_*` callbacks can
safely perform side effects (send emails, provision access, update billing
state) without worrying about duplicates.

Transition timestamps (`paid_at`, `canceled_at`, `failed_at`, `expired_at`,
`refunded_at`, `mandated_at`) are set once when the transition is first
observed and never overwritten.

### Rate limiting

The webhook endpoint is publicly accessible by design. Consider rate limiting
it at the infrastructure level:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("mollie_webhooks", limit: 100, period: 60) do |req|
  req.path == "/mollie_pay/webhooks" && req.post? && req.ip
end
```

## Reacting to events

Override any of these no-op methods in your billable model:

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable

  # One-off payment confirmed
  def on_mollie_payment_paid(payment)
  end

  # Payment failed (card declined, insufficient funds, etc.)
  def on_mollie_payment_failed(payment)
  end

  # Payment was canceled before completion
  def on_mollie_payment_canceled(payment)
  end

  # Payment expired (customer never completed checkout)
  def on_mollie_payment_expired(payment)
  end

  # First payment confirmed — mandate is now established.
  # Safe to call mollie_subscribe after this.
  def on_mollie_first_payment_paid(payment)
  end

  # Recurring subscription payment succeeded
  def on_mollie_subscription_charged(payment)
  end

  # Subscription was canceled (by you or by the customer)
  def on_mollie_subscription_canceled(subscription)
  end

  # Payment failed, Mollie suspended the subscription.
  # The subscription will resume when the next payment succeeds.
  def on_mollie_subscription_suspended(subscription)
  end

  # Fixed-term subscription has completed all payments
  def on_mollie_subscription_completed(subscription)
  end

  # Payment mandate was created and validated
  def on_mollie_mandate_created(mandate)
  end

  # Refund has been processed by Mollie
  def on_mollie_refund_processed(refund)
  end
end
```

Each hook receives the relevant MolliePay model instance. These hooks fire
only once per status transition — never on duplicate webhooks.

## Data model

| Table | Key columns | Purpose |
|---|---|---|
| `mollie_pay_customers` | `mollie_id`, `owner` (polymorphic) | Links your model to a Mollie customer |
| `mollie_pay_mandates` | `mollie_id`, `status`, `method` | Stored payment methods (SEPA, card, etc.) |
| `mollie_pay_subscriptions` | `mollie_id`, `status`, `amount`, `interval` | Recurring billing agreements |
| `mollie_pay_payments` | `mollie_id`, `status`, `amount`, `sequence_type` | Individual payment records |
| `mollie_pay_refunds` | `mollie_id`, `status`, `amount` | Refunds against payments |
| `mollie_pay_webhook_events` | `mollie_id`, `resource_type`, `processed_at` | Inbound webhook log with processing state |

Only fields needed for business logic and state queries are stored locally.
Display data lives in Mollie and is fetched via `mollie_record`.

### Relationships

```
Owner (your model)
  └── Customer (1:1, polymorphic)
        ├── Payments (1:N)
        │     └── Refunds (1:N)
        ├── Subscriptions (1:N)
        │     └── Payments (1:N, optional)
        └── Mandates (1:N)
```

### Statuses

| Model | Valid statuses |
|---|---|
| Payment | `open`, `pending`, `authorized`, `paid`, `failed`, `canceled`, `expired` |
| Subscription | `pending`, `active`, `suspended`, `canceled`, `completed` |
| Mandate | `pending`, `valid`, `invalid` |
| Refund | `queued`, `pending`, `processing`, `refunded`, `failed` |

### Scopes

```ruby
MolliePay::Payment.paid             # status: paid
MolliePay::Payment.failed           # status: failed
MolliePay::Payment.open             # status: open
MolliePay::Payment.recurring        # sequence_type: recurring
MolliePay::Payment.first_payments   # sequence_type: first

MolliePay::Subscription.active
MolliePay::Subscription.canceled
MolliePay::Subscription.suspended

MolliePay::Mandate.valid_status
MolliePay::Refund.refunded

MolliePay::WebhookEvent.processed
MolliePay::WebhookEvent.failed
MolliePay::WebhookEvent.pending
```

## Errors

| Error | Raised when |
|---|---|
| `MolliePay::ConfigurationError` | `api_key` or `host` is missing at boot, or no `redirect_url` is available when creating a payment |
| `MolliePay::MandateRequired` | `mollie_subscribe` is called without a valid mandate |
| `MolliePay::SubscriptionNotFound` | `mollie_cancel_subscription` is called without an active subscription |

All inherit from `MolliePay::Error < StandardError`.

## Configuration reference

| Option | Required | Default | Description |
|---|---|---|---|
| `api_key` | Yes | — | Your Mollie API key (`test_*` or `live_*`) |
| `host` | Yes | — | Your application's public URL (e.g. `https://yourapp.com`). Used to build the webhook URL and default redirect URL. |
| `default_redirect_path` | No | — | Path where Mollie sends customers back after payment (e.g. `/payments/:id`). `:id` is replaced with the local payment ID. Combined with `host` to form the full URL. Per-call `redirect_url:` overrides this. |
| `currency` | No | `"EUR"` | ISO 4217 currency code for new payments/subscriptions |

## Testing

MolliePay uses Minitest with fixtures. WebMock is loaded to prevent real HTTP
in tests.

```sh
bin/rails test              # full suite
bin/rails test test/models  # models only
```

### Testing your host app

MolliePay ships test helpers for Minitest that stub all Mollie API calls. Add
to your `test/test_helper.rb`:

```ruby
require "mollie_pay/test_helper"

class ActiveSupport::TestCase
  include MolliePay::TestHelper
end
```

This gives you stub helpers and fake response builders in all your tests.

#### Stub helpers

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

#### Fake response builders

Build individual Mollie response objects when you need more control:

```ruby
response = fake_mollie_payment(id: "tr_test123", status: "paid")
response = fake_mollie_customer(id: "cst_test123")
response = fake_mollie_subscription(id: "sub_test123", status: "active")
response = fake_mollie_refund(id: "re_test123", status: "queued")
```

All IDs default to random values (`tr_test<hex>`, etc.) when not specified.

#### Available helpers

| Helper | Stubs | Default response |
|---|---|---|
| `stub_mollie_payment_create` | `Mollie::Payment.create` | `status: "open"`, random ID and checkout URL |
| `stub_mollie_customer_and_payment_create` | `Mollie::Customer.create` + `Mollie::Payment.create` | Both with random IDs |
| `stub_mollie_subscription_create` | `Mollie::Customer::Subscription.create` | `status: "active"`, random ID |
| `stub_mollie_subscription_cancel` | `Mollie::Customer::Subscription.cancel` | Returns nil |
| `stub_mollie_refund_create` | `Mollie::Refund.create` | `status: "queued"`, random ID |

#### WebMock-based API stubs

For integration tests that should exercise the full Mollie SDK pipeline (JSON
parsing, object construction, HTTP handling), use the `webmock_mollie_*` helpers.
These stub the actual HTTP endpoints with realistic Mollie API v2 HAL+JSON
responses. Requires `webmock` in your test dependencies.

```ruby
class OrganizationIntegrationTest < ActiveSupport::TestCase
  test "payment creation through full SDK pipeline" do
    webmock_mollie_payment_create do
      payment = @org.mollie_pay_once(amount: 5000, description: "Test")
      assert_equal "tr_test1234AB", payment.mollie_id
      assert_equal "https://www.mollie.com/payscreen/select-method/test1234AB", payment.checkout_url
    end
  end

  test "new customer and payment" do
    webmock_mollie_customer_and_payment_create do
      payment = new_org.mollie_pay_once(amount: 1000, description: "Setup")
      assert_equal "cst_test1234AB", new_org.reload.mollie_customer.mollie_id
    end
  end

  test "subscription" do
    webmock_mollie_subscription_create do
      subscription = @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")
      assert_equal "sub_test1234AB", subscription.mollie_id
    end
  end

  test "cancel subscription" do
    webmock_mollie_subscription_cancel(subscription_id: "sub_acme123") do
      @org.mollie_cancel_subscription
    end
  end

  test "refund" do
    webmock_mollie_refund_create do
      refund = @org.mollie_refund(payment)
      assert_equal "re_test1234AB", refund.mollie_id
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
the full SDK including JSON parsing — use them for integration tests or when
debugging SDK interactions.

## Active Job

MolliePay requires Active Job for webhook processing. Configure your queue
adapter in `config/application.rb`:

```ruby
config.active_job.queue_adapter = :solid_queue # or :sidekiq, :good_job, etc.
```

Webhook jobs are enqueued on the `:default` queue. Processing includes:

- **Deduplication:** duplicate webhooks are skipped at the controller level
- **Retry policy:** polynomial backoff, up to 5 attempts on Mollie API and database errors
- **Discard policy:** Mollie 404s (resource not found) are discarded immediately
- **Idempotency guard:** already-processed events are skipped on retry
- **Programming errors** (`NoMethodError`, etc.) bubble up immediately without marking the event as failed

## License

MIT
