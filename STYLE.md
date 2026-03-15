# STYLE.md

Code style guide for `mollie_pay`. Follows 37signals and Rails idioms strictly.
When in doubt, read the Rails source. When still in doubt, do less.

---

## Ruby

### Clarity over cleverness

Write code that a junior Rails developer can read top to bottom without
stopping. If you need a comment to explain what a line does, rewrite the line.

```ruby
# Bad
payments.select(&:paid?).map(&:amount).sum

# Good
payments.paid.sum(:amount)
```

### One level of abstraction per method

A method either calls other methods or does work. Not both.

```ruby
# Bad
def process!
  object = Mollie::Payment.get(mollie_id)
  payment = Payment.find_or_initialize_by(mollie_id: object.id)
  payment.update!(status: object.status, amount: (object.amount.value.to_d * 100).to_i)
  payment.customer.owner.on_mollie_payment_paid(payment) if object.status == "paid"
end

# Good
def process!
  mollie_object = fetch_from_mollie
  update!(resource_type: resolved_resource_type(mollie_object))
  sync_from_mollie(mollie_object)
  mark_processed!
end
```

### Predicate methods return booleans

Use `?` suffix. Return `true` or `false`, never a truthy object.

```ruby
# Bad
def paid?
  paid_at
end

# Good
def paid?
  status == "paid"
end
```

### No unnecessary guards

Trust your data model. Validations and database constraints mean you do not
need to defensively check for nil everywhere.

```ruby
# Bad
def amount_in_euros
  return 0 if amount.nil?
  amount / 100.0
end

# Good — amount is validated not null
def amount_in_euros
  amount / 100.0
end
```

### Endless methods for simple readers

Use Ruby 3 endless method syntax for single-expression readers and predicates.

```ruby
def paid?         = status == "paid"
def amount_in_euros = amount / 100.0
def mollie_record = Mollie::Payment.get(mollie_id)
```

Not for anything with logic, branching or side effects.

### Expanded conditionals over guard clauses

Prefer `if/else` blocks over guard clauses. Guard clauses are acceptable
only for early returns at the very top of a method — never mid-method.

```ruby
# Bad — guard clause mid-method
def process!
  mollie_object = fetch_from_mollie
  return if mollie_object.nil?
  sync_from_mollie(mollie_object)
  mark_processed!
end

# Good — expanded conditional
def process!
  mollie_object = fetch_from_mollie

  if mollie_object
    sync_from_mollie(mollie_object)
    mark_processed!
  else
    mark_failed!
  end
end

# Also good — guard at the top for preconditions
def process!
  raise MolliePay::Error, "Already processed" if processed?

  mollie_object = fetch_from_mollie
  sync_from_mollie(mollie_object)
  mark_processed!
end
```

### Method ordering

Within a class or module, order methods by visibility and invocation:

1. Constants
2. Associations (`belongs_to`, `has_many`)
3. Validations
4. Scopes
5. Class methods
6. Public instance methods
7. `private` keyword
8. Private methods — ordered by invocation order, callers before callees

```ruby
class Payment < ApplicationRecord
  STATUSES = %w[ open paid failed ].freeze

  belongs_to :customer

  validates :status, inclusion: { in: STATUSES }

  scope :paid, -> { where(status: "paid") }

  def self.record_from_mollie(mp)
    find_or_initialize_by(mollie_id: mp.id).tap { |p| p.update!(...) }
  end

  def paid? = status == "paid"

  def notify_billable
    send_payment_hook
  end

  private
    def send_payment_hook
      customer.owner.public_send(hook_method, self)
    end

    def hook_method
      "on_mollie_payment_#{status}"
    end
end
```

### Private means private

Everything that is not part of the public interface is `private`. No
`protected`. Default to private and promote to public deliberately.
Indent private methods under the `private` keyword (37signals house style).

---

## Rails

### Fat models, thin controllers

Controllers find things and render things. Business logic belongs on the model.

```ruby
# Bad — logic in controller
def create
  customer = Mollie::Customer.create(name: current_org.name, email: current_org.email)
  mc = MolliePay::Customer.create!(owner: current_org, mollie_id: customer.id)
  redirect_to billing_path
end

# Good — model owns the behaviour
def create
  current_org.mollie_customer!
  redirect_to billing_path
end
```

### Scopes over class methods for queries

Use `scope` for simple query compositions. Use class methods only when the
query requires conditional logic.

```ruby
# Good
scope :active,   -> { where(status: "active") }
scope :paid,     -> { where(status: "paid") }

# Also good — conditional logic warrants a class method
def self.record_from_mollie(mp)
  find_or_initialize_by(mollie_id: mp.id).tap { |p| p.update!(...) }
end
```

### Callbacks are for model lifecycle only

`before_save`, `after_create` etc. are for things that are always true about
the model regardless of context. Not for side effects like sending emails or
calling APIs. Those belong in the caller.

```ruby
# Bad
after_create :notify_billable

# Good — explicit call where the transition happens
def self.record_from_mollie(mp)
  payment = find_or_initialize_by(mollie_id: mp.id)
  payment.update!(...)
  payment.notify_billable
  payment
end
```

### `find_or_initialize_by` + `update!` over conditional create/update

Idempotent by default. Mollie webhooks can fire multiple times for the same
event.

```ruby
# Good
def self.record_from_mollie(mp)
  find_or_initialize_by(mollie_id: mp.id).tap do |payment|
    payment.update!(status: mp.status, ...)
  end
end
```

### Raise named errors

Define errors as subclasses of `MolliePay::Error`. Never raise `RuntimeError`
or bare `StandardError` from intentional failure paths.

```ruby
# Bad
raise "No mandate on file"

# Good
raise MolliePay::MandateRequired, "No valid mandate on file"
```

### `exists?` for presence checks on AR relations

Do not load records just to check they exist.

```ruby
# Bad
mollie_customer&.subscriptions&.active&.first&.present?

# Good
mollie_customer&.subscriptions&.active&.exists?
```

### Time

- `Time.current` — always, never `Time.now`
- `Date.today` — for dates
- Set transition timestamps once on first observation, never overwrite

```ruby
paid_at: mp.status == "paid" && !was_paid ? Time.current : payment.paid_at
```

---

## Controllers

### REST only — new resource over custom action

No custom action names. If behaviour does not map to standard CRUD on the
current resource, introduce a new resource. This is how you stay RESTful
without `member` or `collection` hacks.

```ruby
# Bad — custom action
resources :subscriptions do
  post :cancel, on: :member
end

# Good — new resource
resources :subscriptions, only: [] do
  resource :cancellation, only: :create
end

# Also good — simple single-resource route
resources :webhooks, only: :create
```

### `params.expect` over `params.require.permit`

Use the Rails 8+ `params.expect` for strong parameters. It is stricter —
raises on missing keys and validates shape in one call.

```ruby
# Bad
params.require(:payment).permit(:amount, :description)

# Good
params.expect(payment: [ :amount, :description ])
```

### Respond fast, work async

Controllers do the minimum and enqueue the rest.

```ruby
def create
  event = WebhookEvent.create!(mollie_id: params[:id])
  ProcessWebhookJob.perform_later(event.id)
  head :ok
end
```

---

## Models

### Constants for finite sets

Every field with a finite set of valid values has a constant.

```ruby
STATUSES       = %w[ open pending authorized paid failed canceled expired ].freeze
SEQUENCE_TYPES = %w[ oneoff first recurring ].freeze
```

Use the constant in validations and anywhere the list is referenced. Never
repeat the string values.

### Validate at the model layer

Every constraint that matters to the business is a validation. Database
constraints back them up, but are not a substitute.

```ruby
validates :status,   inclusion: { in: STATUSES }
validates :amount,   presence: true, numericality: { greater_than: 0 }
validates :mollie_id, presence: true, uniqueness: true
```

### No `attr_accessor` for persisted data

If it belongs to the record, it has a database column. `attr_accessor` is for
transient, non-persisted values only.

---

## Money

Amounts are **always integers (cents)** in Ruby and in the database.
Never floats. Never BigDecimal except at the conversion boundary.

```ruby
# Database: integer cents
# Conversion to Mollie format:
def mollie_amount
  { currency: currency, value: format("%.2f", amount / 100.0) }
end

# Conversion from Mollie format:
def self.mollie_value_to_cents(mollie_amount)
  (mollie_amount.value.to_d * 100).to_i
end
```

---

## Testing

### Fixtures, not factories

Fixtures define the steady state of the world. Every test starts from the
same known state.

```yaml
# test/fixtures/mollie_pay/payments.yml
acme_first:
  customer: acme
  mollie_id: tr_first123
  status: paid
  amount: 1000
  currency: EUR
  sequence_type: first
  paid_at: <%= 1.week.ago %>
```

### Test behaviour, not implementation

Assert what the system does, not how it does it.

```ruby
# Bad
test "calls Mollie::Payment.get" do
  Mollie::Payment.expects(:get).once
  event.process!
end

# Good
test "process! marks event processed" do
  event.process!
  assert event.processed?
end
```

### Stub at the boundary

External API calls are stubbed. Everything else runs for real.

```ruby
# Stub the Mollie API client, let the Rails code run
mollie_object = OpenStruct.new(id: "tr_123", status: "paid", ...)
Mollie::Payment.stub(:get, mollie_object) do
  event.process!
end
```

### Plain stubs with `stub` blocks

Use `Model.stub(:method, value) { }` from Minitest. No Mocha, no RSpec mocks,
no `stub_any_instance`. Use `Object.new` with `define_singleton_method` for
mock objects.

```ruby
mock_event = Object.new
mock_event.define_singleton_method(:process!) { true }

WebhookEvent.stub(:find, mock_event) do
  ProcessWebhookJob.perform_now(event.id)
end
```

### One assertion per test where possible

Name the test precisely. If you need multiple assertions to describe one
behaviour, that is fine — but each test should have a single concern.

```ruby
test "paid? returns true when status is paid" do
  assert mollie_pay_payments(:acme_first).paid?
end

test "paid? returns false when status is open" do
  assert_not mollie_pay_payments(:acme_oneoff).paid?
end
```

---

## Naming

| Thing | Convention |
|---|---|
| Models | `Customer`, `Payment`, `Subscription` |
| Concerns | adjective-style capabilities: `Billable`, not `BillingManager` |
| Scopes | named for the state: `active`, `paid`, `valid_status` |
| Predicates | `paid?`, `active?`, `mandated?` |
| Class methods syncing from Mollie | `record_from_mollie` |
| Hook methods on Billable | `on_mollie_*` |
| Mollie fetch method | `mollie_record` |
| Amount conversion | `amount_in_euros`, `mollie_amount`, `mollie_value_to_cents` |
| Async/sync pairs | `_later` suffix for async, `_now` for sync |

---

## What does not belong here

- Service objects (`app/services/`)
- Presenters or view objects
- Form objects
- Interactors or use case objects
- DSLs for defining billing plans
- Anything that requires a new gem to understand

If the pattern does not exist in a standard Rails application, it does not
belong in this engine.
