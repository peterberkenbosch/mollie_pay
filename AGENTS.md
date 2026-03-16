# AGENTS.md

Instructions for AI agents working in this codebase. Read fully before
making any changes.

---

## What this project is

`mollie_pay` is a mountable Rails engine that provides Mollie payment
integration for SaaS applications. It handles customers, mandates,
subscriptions, one-off payments, refunds and webhooks. It is headless —
no views, one webhook endpoint, pure business logic.

---

## Non-negotiable rules

- **No service objects.** Behaviour belongs on the model that owns the data.
  If you are reaching for `app/services/`, stop and put the method on the
  model instead.
- **No RSpec, no FactoryBot, no Mocha.** Tests use Minitest and fixtures only.
  `bin/rails test` is the only test command.
- **No gems without justification.** Every dependency must earn its place.
  The only runtime dependencies are `rails` and `mollie-api-ruby`.
- **No custom action names.** Controllers use only standard REST actions:
  `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`.
  If you need a new action, introduce a new resource instead.
- **No JavaScript, no asset pipeline, no views.** This engine is headless.
  Delete anything the generator adds in `app/assets`, `app/helpers` or
  `app/views`.
- **Amounts are always integers (cents).** Never floats. Never strings.
  Convert at the Mollie API boundary only, using `mollie_amount` and
  `mollie_value_to_cents`.

---

## Architecture

```
app/
  controllers/mollie_pay/
    application_controller.rb   # inherits ActionController::Base directly
    webhooks_controller.rb      # create only
  jobs/mollie_pay/
    application_job.rb
    process_webhook_job.rb
  models/mollie_pay/
    application_record.rb       # shared mollie_value_to_cents
    billable.rb                 # concern included by host app model
    customer.rb
    mandate.rb
    payment.rb
    refund.rb
    subscription.rb
    webhook_event.rb            # owns process! — the webhook entry point
lib/
  mollie_pay/
    configuration.rb
    engine.rb
    errors.rb
    version.rb
  mollie_pay.rb
```

There is no `app/services/`. There are no presenters, decorators, form
objects or interactors.

---

## How the webhook flow works

```
POST /mollie_pay/webhooks
  → WebhooksController#create
  → validates mollie_id format: (tr|sub|re)_[a-zA-Z0-9]+
  → WebhookEvent.create!(mollie_id: params.expect(:id))
  → ProcessWebhookJob.perform_later(event.id)
  → head :ok

ProcessWebhookJob#perform
  → skips if event already processed
  → event.process!
  → clears failed state if retrying
  → fetches object from Mollie API by ID prefix (tr_, sub_, re_)
  → routes to Payment.record_from_mollie / Subscription.record_from_mollie / Refund.record_from_mollie
  → each class method upserts the local record
  → fires on_mollie_* hook ONLY if status actually changed
  → marks event processed
  → on failure: marks event failed (truncated error), re-raises for ActiveJob retry
  → discards Mollie::ResourceNotFoundError (404) — no retry
```

Mollie sends only an `id` in the webhook POST body. We always fetch the full
object from the API. The API key is the verification — no signature needed.

**Idempotency:** hooks fire only on actual status transitions. Duplicate
webhooks update the record but do not re-trigger hooks. Transition timestamps
are set once, never overwritten.

---

## Models

Each model has three things and nothing more:

1. **Constants** — single source of truth for valid status strings
2. **Scopes** — answer the business questions that need SQL
3. **`mollie_record`** — lazy fetch from Mollie API for display data

Timestamps for state transitions (`paid_at`, `canceled_at`, etc.) are set
once when the transition is first observed, never overwritten.

### `record_from_mollie` pattern

Every model that is synced from Mollie has a class method:

```ruby
def self.record_from_mollie(mollie_object)
  customer = Customer.includes(:owner).find_by!(...)
  record = find_or_initialize_by(mollie_id: mollie_object.id)
  previous_status = record.status
  record.update!(...)
  record.notify_billable if record.status != previous_status
  record
end
```

The `previous_status` check ensures hooks fire only on actual state
transitions. The `includes(:owner)` avoids N+1 queries when calling hooks.

`mollie_value_to_cents` is defined on `ApplicationRecord` and shared by all
models that convert Mollie amounts.

---

## Billable concern

The public API for host app developers. Include it in one model:

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable
end
```

Public methods:
- `mollie_pay_once(amount:, description:, redirect_url: nil, method: nil)` → returns `Payment` with `checkout_url`
- `mollie_pay_first(amount:, description:, redirect_url: nil, method: nil)` → returns `Payment` with `checkout_url`
- `mollie_subscribe(amount:, interval:, description:)`
- `mollie_cancel_subscription`
- `mollie_refund(payment, amount: nil)`
- `mollie_subscribed?`
- `mollie_mandated?`
- `mollie_subscription`
- `mollie_mandate`
- `mollie_payments`

Event hooks (override in host model, all no-ops by default):
- `on_mollie_payment_paid`
- `on_mollie_payment_failed`
- `on_mollie_payment_canceled`
- `on_mollie_payment_expired`
- `on_mollie_first_payment_paid`
- `on_mollie_subscription_charged`
- `on_mollie_subscription_canceled`
- `on_mollie_subscription_suspended`
- `on_mollie_subscription_completed`
- `on_mollie_mandate_created`
- `on_mollie_refund_processed`

---

## Configuration

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"]
  config.default_redirect_path = "/payments/:id"
  config.currency              = "EUR"
end
```

The engine initializer wires `api_key` to `Mollie::Client.configure`
automatically. No separate Mollie SDK setup is needed.

---

## Testing

- Framework: **Minitest** (Rails default)
- Fixtures only — no factories
- WebMock is loaded for all tests — no real HTTP ever leaves the test suite
- Mollie API objects are stubbed with plain `OpenStruct` or `Object.new` with
  `define_singleton_method`
- Use `Model.stub(:method, value)` blocks for isolation — never Mocha

### Running tests

```sh
bin/rails test              # full suite
bin/rails test test/models  # models only
bin/rails test test/controllers
bin/rails test test/jobs
```

---

## Conventions

- Prefer `find_or_initialize_by` + `update!` over separate `create` and `update` paths
- Prefer `exists?` over `present?` for AR queries
- Use `Time.current` not `Time.now`
- Use `Date.today` not `Date.new`
- Raise named errors from `MolliePay::Error` subclasses, never raw `RuntimeError`
- All money amounts: **cents as Integer** in the database, converted to Mollie
  format only at the API call boundary
- Use `params.expect` not `params.require.permit` (Rails 8+)
- Expanded conditionals over guard clauses — guard clauses only for early
  returns at the top of a method, never mid-method
- Method ordering: constants → associations → validations → scopes →
  class methods → public instance methods → `private` → private methods
  ordered by invocation order (callers before callees)
- Concerns named as capabilities: adjective-style (`Billable`), not
  noun-style

---

## What not to add

- Views of any kind
- JavaScript
- CSS
- Custom non-REST controller actions
- Service objects
- Presenters or decorators
- Form objects
- Additional gems unless absolutely unavoidable
