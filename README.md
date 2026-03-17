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
- **Idempotent.** Hooks fire only on actual status transitions. Duplicate webhooks are handled safely.
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

### Cancel and refund

```ruby
current_organization.mollie_cancel_subscription
current_organization.mollie_refund(payment)              # full
current_organization.mollie_refund(payment, amount: 500) # partial
```

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

See [docs/webhooks.md](docs/webhooks.md) for details on verification,
idempotency, Active Job configuration, and rate limiting.

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
end
```

All hooks: `on_mollie_payment_paid`, `on_mollie_payment_failed`,
`on_mollie_payment_canceled`, `on_mollie_payment_expired`,
`on_mollie_first_payment_paid`, `on_mollie_subscription_charged`,
`on_mollie_subscription_canceled`, `on_mollie_subscription_suspended`,
`on_mollie_subscription_completed`, `on_mollie_mandate_created`,
`on_mollie_refund_processed`.

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
- [Webhooks](docs/webhooks.md) — webhook flow, idempotency, Active Job
- [Testing](docs/testing.md) — stub helpers and WebMock helpers
- [Releasing](docs/RELEASING.md) — release process

## Requirements

- Ruby 3.2+
- Rails 8.0+
- Active Job (any queue adapter)
- A [Mollie](https://my.mollie.com/dashboard/signup/7878281?lang=nl) account and API key

## License

MIT
