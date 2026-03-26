# MolliePay

A mountable Rails engine for Mollie payments in SaaS applications. Handles
customers, mandates, subscriptions, one-off payments, refunds, chargebacks
and webhooks. You write the business logic; MolliePay handles the Mollie
plumbing.

Rails 8.1+, Mollie-native.

## Philosophy

- **Headless.** No views, no UI opinions. One mounted webhook endpoint, nothing else.
- **Lean data model.** Only business-critical fields are stored locally. Everything else is fetched from Mollie on demand via `record.mollie_record`.
- **Hooks, not events.** Override plain Ruby methods in your model. No event bus, no pub/sub, no callbacks to register.
- **Boring Rails.** Models do the work. No service objects, no form objects, no interactors.
- **Idempotent.** Hooks fire only on actual state transitions. Duplicate webhooks are handled safely.
- **Cents, not floats.** All amounts are stored as integers (cents). Conversion happens only at the Mollie API boundary.

## Installation

```ruby
gem "mollie_pay"
```

```sh
bundle install
bin/rails generate mollie_pay:install
```

Mount the engine in `config/routes.rb`:

```ruby
mount MolliePay::Engine => "/mollie_pay"
```

Configure in `config/initializers/mollie_pay.rb`:

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"]
  config.default_redirect_path = "/payments/:id"
  config.currency              = "EUR"
end
```

## Setup

Include `MolliePay::Billable` in your paying model:

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable
end
```

## Usage

### First payment (establishes mandate)

```ruby
payment = current_organization.mollie_pay_first(
  amount: 1000, description: "Activation fee"
)
redirect_to payment.checkout_url
```

### Subscribe (requires mandate)

```ruby
current_organization.mollie_subscribe(
  amount: 2500, interval: "1 month", description: "Monthly plan"
)
```

Named subscriptions for multiple concurrent plans:

```ruby
current_organization.mollie_subscribe(
  amount: 1000, interval: "1 month", description: "Analytics",
  name: "analytics_addon"
)
```

### One-off payment

```ruby
payment = current_organization.mollie_pay_once(
  amount: 7500, description: "Extra service"
)
redirect_to payment.checkout_url
```

### Upgrade or downgrade

```ruby
current_organization.mollie_swap_subscription(amount: 4999)
current_organization.mollie_swap_subscription(amount: 4999, interval: "1 year")
current_organization.mollie_swap_subscription(name: "analytics_addon", amount: 1999)
```

Changes take effect on the next billing cycle. See [docs/api.md](docs/api.md)
for proration guidance.

### Mandates

Create SEPA Direct Debit mandates directly (for mandate migrations or
pre-existing bank relationships):

```ruby
mandate = current_organization.mollie_create_mandate(
  method: "directdebit",
  consumer_name: "Jane Doe",
  consumer_account: "NL55INGB0000000000",
  signature_date: Date.today
)
```

> **Important:** Direct mandate creation requires prior customer authorization.
> See [docs/mandates.md](docs/mandates.md) for SEPA compliance requirements.
> For most applications, use `mollie_pay_first` instead — Mollie's checkout
> handles consent and bank authentication automatically.

Revoke a mandate:

```ruby
current_organization.mollie_revoke_mandate(mandate)
```

### Customer management

```ruby
current_organization.mollie_update_customer(name: "New Name", email: "new@example.com")
current_organization.mollie_delete_customer  # cascades to all local records
```

### Cancel, update, and refund

```ruby
current_organization.mollie_cancel_subscription
current_organization.mollie_cancel_payment(payment)
current_organization.mollie_update_payment(payment, description: "Updated")
current_organization.mollie_refund(payment)              # full
current_organization.mollie_refund(payment, amount: 500) # partial
```

### Payment methods

```ruby
MolliePay.payment_methods                        # all enabled methods
MolliePay.payment_methods(amount: 1000)          # filtered by amount (cents)
MolliePay.payment_method("ideal")                # single method details
```

### Sales Invoices (beta)

Create, retrieve, and manage sales invoices through Mollie's Sales Invoices API.
No local model is stored — all data lives on Mollie's side.

```ruby
# Create a draft invoice
invoice = current_organization.mollie_create_sales_invoice(
  lines: [{ description: "Pro plan", quantity: 1, vat_rate: "21.00", unit_price: 8900 }]
)

# Create and send immediately
invoice = current_organization.mollie_create_sales_invoice(
  status: "issued",
  lines: [{ description: "Pro plan", quantity: 1, vat_rate: "21.00", unit_price: 8900 }],
  email_details: { subject: "Your invoice", body: "Please pay within 30 days" }
)

# With explicit recipient (overrides auto-populated fields)
invoice = MolliePay.create_sales_invoice(
  status: "draft",
  recipient: { type: "business", organization_name: "Acme B.V.", email: "billing@acme.nl" },
  lines: [{ description: "Consulting", quantity: 10, vat_rate: "21.00", unit_price: 15000 }],
  payment_term: "30 days",
  memo: "Thank you for your business!"
)

# Retrieve, list, update, delete
invoice = MolliePay.sales_invoice("invoice_abc123")
invoices = MolliePay.sales_invoices
MolliePay.update_sales_invoice("invoice_abc123", memo: "Updated memo")
MolliePay.delete_sales_invoice("invoice_abc123")  # draft only
```

Line item `unit_price` accepts cents (integer) and is converted automatically.
The Billable convenience method auto-populates the recipient from your model's
`name` and `email` attributes.

### Query state

```ruby
org.mollie_subscribed?      # => true/false
org.mollie_mandated?        # => true/false
org.mollie_subscription     # => MolliePay::Subscription or nil
org.mollie_mandate          # => MolliePay::Mandate or nil
org.mollie_payments.paid    # ActiveRecord relation
```

## Webhooks

Point Mollie to `POST https://yourapp.com/mollie_pay/webhooks`. MolliePay
validates the ID, enqueues a background job, and responds `200 OK` immediately.
The job fetches the current state from Mollie and upserts the local record.
Chargebacks are detected automatically via payment amount comparison.

See [docs/webhooks.md](docs/webhooks.md) for details on verification,
idempotency, chargeback detection, Active Job configuration, and rate limiting.

## Reacting to events

Override hooks in your billable model:

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable

  def on_mollie_first_payment_paid(payment)
    # Mandate established — safe to subscribe
  end

  def on_mollie_payment_paid(payment)
    # One-off payment confirmed
  end

  def on_mollie_subscription_charged(payment)
    # Recurring payment succeeded
  end

  def on_mollie_subscription_canceled(subscription)
    # Subscription ended
  end

  def on_mollie_refund_processed(refund)
    # Refund completed
  end

  def on_mollie_chargeback_received(chargeback)
    # Chargeback filed — take action
  end

  def on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:)
    # Plan changed — calculate proration if needed
  end
end
```

All hooks: `on_mollie_payment_paid`, `on_mollie_payment_authorized`,
`on_mollie_payment_failed`, `on_mollie_payment_canceled`,
`on_mollie_payment_expired`, `on_mollie_first_payment_paid`,
`on_mollie_subscription_charged`, `on_mollie_subscription_canceled`,
`on_mollie_subscription_suspended`, `on_mollie_subscription_completed`,
`on_mollie_mandate_created`, `on_mollie_refund_processed`,
`on_mollie_chargeback_received`, `on_mollie_chargeback_reversed`,
`on_mollie_subscription_swapped`.

## Testing

```ruby
# test/test_helper.rb
require "mollie_pay/test_helper"

class ActiveSupport::TestCase
  include MolliePay::TestHelper
end
```

```ruby
stub_mollie_payment_create do
  payment = @org.mollie_pay_once(amount: 5000, description: "Test")
  assert_equal "open", payment.status
end
```

See [docs/testing.md](docs/testing.md) for the full helper reference.

## Documentation

- [Tutorial](docs/tutorial.md) — step-by-step guide
- [API Reference](docs/api.md) — data model, statuses, scopes, errors, configuration
- [Webhooks](docs/webhooks.md) — webhook flow, chargeback detection, idempotency, Active Job
- [Mandates](docs/mandates.md) — SEPA DD mandate consent, compliance, web signature collection
- [Testing](docs/testing.md) — stub helpers and WebMock helpers
- [Releasing](docs/RELEASING.md) — release process

## Requirements

- Ruby 3.2+
- Rails 8.1+
- Active Job (any queue adapter)
- A [Mollie](https://my.mollie.com/dashboard/signup/7878281?lang=nl) account and API key

## License

MIT
