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

## Engine family charter

`mollie_pay` is a member of the engine family and follows the shared charter:
https://github.com/pbcbv/engine-family/blob/main/ENGINE-FAMILY.md (see also ADR 003).
Two conventions this repo adopts from it:

- **UUIDv7 string primary keys.** Every model has a `:string` PK assigned by the copied
  `MolliePay::HasUuid` concern (`SecureRandom.uuid_v7`, `before_create`), included via
  `MolliePay::ApplicationRecord`. Foreign-key and polymorphic `*_id` columns (including the
  host `owner`) are `:string`. Greenfield — no integer-PK backfill.
- **Headless with one exception.** The engine ships no controllers or views beyond the
  Mollie webhook controller and its jobs, which are the one allowed mountable exception to
  the headless rule.

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
- **Amounts are always exact `BigDecimal`.** Never cents, never floats. Stored in
  TEXT-affinity `:string` columns via the registered `:money` cast
  (`MolliePay::DecimalMoneyType`); never a `:decimal` column (SQLite NUMERIC
  affinity stores REAL/float and loses precision). Convert to Mollie's wire format
  only at the API boundary, using `mollie_amount` and `mollie_value_to_decimal`.

---

## Architecture

There is no `app/services/`. There are no presenters, decorators, form
objects or interactors.

---

## How the webhook flow works

```
POST /mollie_pay/webhooks
  → WebhooksController#create
  → validates mollie_id format: (tr|sub|re|stl)_[a-zA-Z0-9]{1,64}
  → ProcessWebhookJob.perform_later(mollie_id)
  → head :ok

ProcessWebhookJob#perform(mollie_id)
  → routes by ID prefix (tr_ → Payment, sub_ → Subscription, re_ → Refund)
  → fetches current state from Mollie API
  → upserts local record via Model.record_from_mollie
  → fires on_mollie_* hook ONLY if status actually changed
  → on failure: ActiveJob retries with polynomial backoff (5 attempts)
  → discards Mollie::ResourceNotFoundError (404) and RecordNotFound — no retry
```

**No `WebhookEvent` model — by design.** There is no intermediate event table.
The controller validates and enqueues. The job does the work. Domain models own
their state. ActiveJob owns retries. This follows the 37signals principle: don't
create mutable infrastructure records when the real state already lives on domain
models (Payment, Subscription, Refund) and the retry/failure tracking already
lives in ActiveJob. Mollie sends only an `id` — we always fetch the full object
from the API. The API key is the verification — no signature needed.

**Do not re-introduce a webhook event model.** If you need an audit trail of
Mollie webhooks, check Mollie's dashboard. If you need to know why a payment is
in a certain state, check the domain model's status and transition timestamps.

**Idempotency:** `record_from_mollie` uses `find_or_initialize_by(mollie_id:)` +
`previous_status` check. Hooks fire only on actual status transitions. Transition
timestamps are set once, never overwritten. Host app hooks should be idempotent.

**Concurrent INSERT race:** `Payment.record_from_mollie` and
`Refund.record_from_mollie` rescue `ActiveRecord::RecordNotUnique` and fall back
to `find_by!`, matching the existing `Subscription.record_from_mollie` pattern.
This handles the case where two concurrent jobs for the same `mollie_id` both
try to create a new record simultaneously.

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

`mollie_value_to_decimal` is defined on `ApplicationRecord` and shared by all
models that convert Mollie amounts (parses Mollie's `value` string to BigDecimal).

---

## Billable concern

The public API for host app developers. Include it in one model:

```ruby
class Organization < ApplicationRecord
  include MolliePay::Billable
end
```

The `included` block sets up these associations automatically:

```ruby
included do
  has_one  :mollie_customer,      class_name: "MolliePay::Customer", as: :owner, dependent: :destroy
  has_many :mollie_subscriptions, through: :mollie_customer, source: :subscriptions, class_name: "MolliePay::Subscription"
  has_many :mollie_payments,      through: :mollie_customer, source: :payments,      class_name: "MolliePay::Payment"
  has_many :mollie_mandates,      through: :mollie_customer, source: :mandates,      class_name: "MolliePay::Mandate"
end
```

**Note:** `class_name` is required on cross-namespace `has_many :through`
associations. Rails cannot resolve engine-namespaced models when the including
model is in the host app namespace.

`mollie_create_mandate` creates a SEPA DD mandate directly and **requires prior
customer consent** — see [docs/mandates.md](docs/mandates.md).

**Named subscriptions:** All subscription methods accept `name:` with a default
of `"default"`. This allows multiple concurrent subscriptions per customer
(e.g., `"default"` + `"analytics_addon"`). A partial unique index prevents
duplicate active/pending subscriptions per name per customer.

Event hooks (`on_mollie_*`) are overridden in the host model and are all no-ops
by default.

---

## Configuration

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"]
  config.default_redirect_path = "/payments/:id"
  config.currency              = "EUR"
  config.webhook_signing_secret = ENV["MOLLIE_WEBHOOK_SIGNING_SECRET"]
end
```

The engine initializer wires `api_key` to `Mollie::Client.configure`
automatically. No separate Mollie SDK setup is needed.

**Next-Gen Webhooks:** Set `webhook_signing_secret` to enable HMAC-SHA256
verification for the `/webhook_events` endpoint. Accepts a string or an
array of strings (for secret rotation). If not set, events are accepted
without verification.

**Note:** `ProcessWebhookEventJob` receives event data with **camelCase**
string keys (e.g., `event["entityId"]`, not `event["entity_id"]`), unlike
classic webhooks where the Mollie SDK converts to snake_case.

---

## Mollie API reference

The official Mollie API Reference at https://docs.mollie.com/reference/overview
is the **source of truth** for all API integration work. Always verify response
structures, field names, and endpoint behaviour against these docs.

**Do not rely solely on `mollie-api-ruby` class definitions.** The gem may not
expose all API fields via `attr_accessor` (e.g., `reason` on chargebacks). The
full response data is always available via `mollie_object.attributes` — a hash
stored by `Mollie::Base` containing every field the API returned.

**Key SDK behaviour:** `Mollie::Util.nested_underscore_keys` converts all API
response keys from camelCase to snake_case. This means:
- The API returns `createdAt`, `paymentId`, `settlementAmount`
- After SDK parsing, these become `created_at`, `payment_id`, `settlement_amount`
- JSON test fixtures must use camelCase (matching the real API)

---

## Testing

- Framework: **Minitest** (Rails default)
- Fixtures only — no factories
- WebMock is loaded for all tests — no real HTTP ever leaves the test suite
- Mollie API objects are stubbed with plain `OpenStruct` or `Object.new` with
  `define_singleton_method`
- Use `Model.stub(:method, value)` blocks for isolation — never Mocha
- JSON test fixtures in `lib/mollie_pay/test_fixtures/` must match real Mollie
  API responses exactly — use **camelCase** keys, include all fields the API
  returns. Never copy fixtures from the `mollie-api-ruby` gem without verifying
  against the live API first.

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
- All money amounts: **exact `BigDecimal`**, stored as text via the `:money` cast,
  converted to Mollie's wire format only at the API call boundary
- Use `params.expect` not `params.require.permit` (Rails 8+)
- Expanded conditionals over guard clauses — guard clauses only for early
  returns at the top of a method, never mid-method
- Method ordering: constants → associations → validations → scopes →
  class methods → public instance methods → `private` → private methods
  ordered by invocation order (callers before callees)
- Concerns named as capabilities: adjective-style (`Billable`), not
  noun-style

---

## Git workflow

- **Squash merge only.** All PRs are merged with `--squash`. Never use regular
  merge commits. The git history must be linear and clean.
- **CI must pass before merging.** Always verify that tests and rubocop pass in
  CI before merging any PR. Use `gh pr checks` to confirm.
- **Force push with lease.** When force-pushing is necessary, always use
  `--force-with-lease`, never `--force`.

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
