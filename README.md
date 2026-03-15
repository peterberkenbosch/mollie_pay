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
- A [Mollie](https://www.mollie.com) account and API key

## Installation

Add to your Gemfile:

```ruby
gem "mollie_pay"
```

Install and run migrations:

```sh
bundle install
bin/rails mollie_pay:install:migrations
bin/rails db:migrate
```

Mount the engine in `config/routes.rb`:

```ruby
mount MolliePay::Engine => "/mollie_pay"
```

Configure in `config/initializers/mollie_pay.rb`:

```ruby
MolliePay.configure do |config|
  config.api_key     = ENV["MOLLIE_API_KEY"]
  config.webhook_url = ENV["MOLLIE_WEBHOOK_URL"] # e.g. https://yourapp.com/mollie_pay/webhooks
  config.currency    = "EUR"                      # default
end
```

The engine validates that `api_key` and `webhook_url` are set, then
configures the Mollie Ruby SDK automatically on boot. A missing key raises
`MolliePay::ConfigurationError` at startup — not deep in a background job.

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
  redirect_url: billing_return_url
)

redirect_to payment.mollie_record.checkout_url
```

The customer completes payment via iDEAL, credit card or another method. Mollie
fires a webhook. MolliePay stores the mandate automatically.

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
  redirect_url: billing_return_url
)
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
payment.mollie_record.checkout_url
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
| `MolliePay::ConfigurationError` | `api_key` or `webhook_url` is missing at boot |
| `MolliePay::MandateRequired` | `mollie_subscribe` is called without a valid mandate |
| `MolliePay::SubscriptionNotFound` | `mollie_cancel_subscription` is called without an active subscription |

All inherit from `MolliePay::Error < StandardError`.

## Configuration reference

| Option | Required | Default | Description |
|---|---|---|---|
| `api_key` | Yes | — | Your Mollie API key (`test_*` or `live_*`) |
| `webhook_url` | Yes | — | Full URL where Mollie sends webhook POSTs |
| `currency` | No | `"EUR"` | ISO 4217 currency code for new payments/subscriptions |

## Testing

MolliePay uses Minitest with fixtures. WebMock is loaded to prevent real HTTP
in tests.

```sh
bin/rails test              # full suite
bin/rails test test/models  # models only
```

### Testing your host app

When testing code that calls MolliePay methods, stub the Mollie API calls:

```ruby
# test/models/organization_test.rb
class OrganizationTest < ActiveSupport::TestCase
  test "subscribing after first payment" do
    org = organizations(:acme)

    # Stub Mollie API responses
    mollie_payment = OpenStruct.new(id: "tr_test123", status: "open")
    Mollie::Payment.stub(:create, mollie_payment) do
      payment = org.mollie_pay_first(
        amount: 1000,
        description: "Setup",
        redirect_url: "https://example.com/return"
      )
      assert_equal "open", payment.status
    end
  end
end
```

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
