---
title: "feat: MolliePay v0.2 — Improvements, Documentation & Tutorial Extension"
type: feat
status: active
date: 2026-03-17
---

# MolliePay v0.2 — Improvements, Documentation & Tutorial Extension

## Overview

MolliePay v0.2 ships three categories of changes that need corresponding documentation updates: new `has_many :through` associations, bug fixes (payment-subscription linking, webhook deduplication), and a new `start_date` parameter on `mollie_subscribe`. The tutorial also needs an "Advanced" section covering payment method selection, credit card first-payment flows, and the patterns discovered during real-world implementation.

This plan covers everything needed to ship a complete v0.2 release.

---

## Part 1: Code Changes Already on Feature Branch

These are implemented on `feat/through-associations-and-bug-fixes` (PR #17 + 1 additional commit):

### 1.1 `has_many :through` Associations on Billable

```ruby
has_many :mollie_subscriptions, through: :mollie_customer, source: :subscriptions, class_name: "MolliePay::Subscription"
has_many :mollie_payments,      through: :mollie_customer, source: :payments,      class_name: "MolliePay::Payment"
has_many :mollie_mandates,      through: :mollie_customer, source: :mandates,      class_name: "MolliePay::Mandate"
```

- `class_name` IS required — Rails cannot resolve namespaced models through a cross-namespace `has_many :through` (verified by test failure without it)
- Removed manual `mollie_payments` method (replaced by through association)
- Rewrote `mollie_subscribed?`, `mollie_subscription`, `mollie_mandated?`, `mollie_mandate` to use through associations instead of safe navigation chains

### 1.2 Payment-to-Subscription Linking

`Payment.record_from_mollie` now links recurring payments to their parent subscription via `subscription_id` from the Mollie payment object. The FK column and `belongs_to` already existed — only the linking code was missing.

### 1.3 Webhook Event Deduplication Fix

- New migration: unique index on `mollie_pay_webhook_events.mollie_id`
- Controller changed from check-then-insert (`unless pending.exists?`) to insert-then-rescue (`create!` + `rescue RecordNotUnique`)
- Fixes: already-processed events being re-created, concurrent webhook race condition

### 1.4 `start_date` Parameter on `mollie_subscribe`

```ruby
def mollie_subscribe(amount:, interval:, description:, start_date: nil)
```

Passes `startDate` to the Mollie API when provided. Used when the first payment already covers the first billing period (credit card flow).

---

## Part 2: Documentation Updates

### 2.1 README.md Updates

**File:** `README.md`

- [ ] **Usage > Subscriptions section**: Add `start_date:` parameter to `mollie_subscribe` example and explain when to use it (credit card first payments that cover the first period)
- [ ] **Usage > Querying section**: Document the new through associations:
  ```ruby
  # Direct traversal (NEW in v0.2)
  user.mollie_subscriptions          # all subscriptions
  user.mollie_subscriptions.active   # active only
  user.mollie_payments               # all payments (was a method, now an association)
  user.mollie_payments.paid          # paid only
  user.mollie_mandates               # all mandates
  user.mollie_mandates.valid_status  # valid only
  ```
- [ ] **Usage > Querying section**: Note that `mollie_payments` is now a `has_many :through` association (not a method). Behavior is identical but it's a real ActiveRecord relation that supports `includes`, `joins`, etc.
- [ ] **Usage > Payments section**: Document the `method:` parameter on `mollie_pay_first` and `mollie_pay_once` for specifying payment methods (`"ideal"`, `"creditcard"`, `"bancontact"`, etc.)
- [ ] **Data Model section**: Add note about the unique index on `mollie_pay_webhook_events.mollie_id` (v0.2 migration)
- [ ] **Webhooks section**: Update deduplication explanation — now uses database unique constraint instead of application-level check. Mention that `RecordNotUnique` is rescued and returns 200 OK.
- [ ] **Upgrading section** (new): Add a "Upgrading to v0.2" section:
  - Run `rails mollie_pay:install:migrations && rails db:migrate` to get the new webhook unique index migration
  - The `mollie_payments` method on Billable was removed — replaced by the identical `has_many :through` association. No code changes needed in host apps.
  - The `mollie_subscribe` method now accepts an optional `start_date:` parameter. Existing calls without it continue to work unchanged.

### 2.2 AGENTS.md Updates

**File:** `AGENTS.md`

- [ ] **Models > Billable section**: Update the `included` block to show the three `has_many :through` associations
- [ ] **Models > Billable section**: Update `mollie_subscribe` signature to include `start_date: nil`
- [ ] **Models > Billable section**: Note that `class_name` is required on cross-namespace through associations (learned from test failure)
- [ ] **Conventions**: Add note about webhook dedup pattern: "Use database unique constraints + rescue RecordNotUnique, not check-then-insert"

### 2.3 STYLE.md Updates

**File:** `STYLE.md`

- [ ] **Rails section**: Add convention for webhook deduplication: prefer unique index + rescue over exists?-then-create (TOCTOU race condition)

### 2.4 CHANGELOG.md (New File)

**File:** `CHANGELOG.md`

- [ ] Create changelog following Keep a Changelog format:

```markdown
# Changelog

All notable changes to MolliePay will be documented in this file.

## [Unreleased]

### Added
- `has_many :mollie_subscriptions`, `has_many :mollie_payments`, `has_many :mollie_mandates` through associations on Billable concern — enables direct traversal like `user.mollie_subscriptions.active`
- `start_date:` optional parameter on `mollie_subscribe` — pass a date to defer the first subscription charge (useful when the first payment already covers the first period)
- `method:` parameter on `mollie_pay_first` and `mollie_pay_once` — specify the Mollie payment method (e.g., `"ideal"`, `"creditcard"`)

### Fixed
- `Payment.record_from_mollie` now links recurring payments to their parent subscription via `subscription_id` from the Mollie payment object
- Webhook event deduplication: replaced application-level check (`pending.exists?`) with database unique index on `mollie_id` + `RecordNotUnique` rescue — fixes race condition with concurrent webhooks and re-processing of already-handled events

### Changed
- `mollie_subscribed?`, `mollie_subscription`, `mollie_mandated?`, `mollie_mandate` now use `has_many :through` associations instead of safe navigation chains
- Removed manual `mollie_payments` method from Billable — replaced by the identical `has_many :through` association

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` to add the unique index on `mollie_pay_webhook_events.mollie_id`
```

---

## Part 3: Tutorial Extension — "Beyond the Basics"

### 3.1 New Tutorial Section: Payment Method Selection

**File:** `docs/tutorial.md` — Add as "Part 6: Payment method selection"

This section teaches users how to let customers choose their payment method and explains the different flows for each.

#### Content Outline:

- [ ] **Introduction**: Explain why payment method selection matters — different methods create different mandate types (credit card → CC recurring, iDEAL → SEPA DD recurring)
- [ ] **The three methods and their flows**:

  | Payment Method | Mollie `method` param | First Payment Amount | Mandate Type | Recurring Via | Subscription Start |
  |---|---|---|---|---|---|
  | iDEAL | `"ideal"` | €0.01 | SEPA Direct Debit | SEPA DD | Immediate |
  | Credit Card | `"creditcard"` | Full plan amount | Credit Card | Credit Card | Next period |
  | SEPA Direct Debit | `"ideal"` (via iDEAL) | €0.01 | SEPA Direct Debit | SEPA DD | Immediate |

- [ ] **Why credit card charges the full amount**: Explain the pattern — credit card can do a "real" first payment that doubles as the first subscription charge. The subscription then starts from the next period via `startDate`. This avoids the €0.01 confusing charge on credit cards.
- [ ] **Why SEPA DD uses iDEAL**: SEPA Direct Debit mandates are typically created through iDEAL (or Bancontact/other methods). The €0.01 iDEAL payment establishes the SEPA DD mandate. Explain this is standard Mollie practice.
- [ ] **Update the pricing view**: Step-by-step code to add radio buttons for payment method selection inside each plan card. Include the `has-[:checked]` Tailwind pattern for visual feedback.

  ```erb
  <%= form_with url: subscription_setup_path, method: :post, data: { turbo: false } do |f| %>
    <%= f.hidden_field :plan, value: key %>
    <fieldset class="mb-4">
      <legend class="text-sm font-medium text-gray-700 mb-2">Payment method</legend>
      <div class="space-y-2">
        <label class="flex items-center gap-3 p-3 border rounded-lg cursor-pointer hover:bg-gray-50 has-[:checked]:border-indigo-500 has-[:checked]:bg-indigo-50">
          <%= f.radio_button :payment_method, "ideal", checked: true, class: "text-indigo-600" %>
          <span class="text-sm font-medium">iDEAL</span>
          <span class="text-xs text-gray-500 ml-auto">Recurring via SEPA Direct Debit</span>
        </label>
        <!-- creditcard and sepa_directdebit options -->
      </div>
    </fieldset>
    <%= f.submit "Get started", class: "w-full bg-indigo-600 ..." %>
  <% end %>
  ```

- [ ] **Update SubscriptionSetupsController**: Show the routing logic — `creditcard` → full amount + `"creditcard"` method, others → €0.01 + `"ideal"` method. Include the `ALLOWED_METHODS` constant for validation.

  ```ruby
  ALLOWED_METHODS = %w[ideal creditcard sepa_directdebit].freeze

  if payment_method == "creditcard"
    amount      = plan_details[:amount]
    mollie_method = "creditcard"
  else
    amount      = 1
    mollie_method = "ideal"
  end
  ```

- [ ] **Update the webhook callback**: Show how `on_mollie_first_payment_paid` detects whether the first payment was the full subscription amount and sets `start_date` accordingly.

  ```ruby
  def on_mollie_first_payment_paid(payment)
    return unless plan.present?
    return if mollie_subscribed?

    plan_details = Plan.find(plan)
    if payment.amount >= plan_details[:amount]
      start_date = Plan.next_period_start(plan)
    end
    subscribe_to_plan!(plan, start_date: start_date)
  end
  ```

- [ ] **Add `Plan.next_period_start`**: Simple helper that calculates the next billing date based on the plan interval.
- [ ] **Update `subscribe_to_plan!`**: Show the `start_date:` keyword being passed through to `mollie_subscribe`.
- [ ] **Testing the flow**: Walk through testing each payment method in Mollie test mode — what to expect from each checkout page, how to verify the mandate type in the Mollie dashboard.

### 3.2 New Tutorial Section: Through Associations

**File:** `docs/tutorial.md` — Add as "Part 7: Using through associations"

- [ ] **Before/after comparison**: Show the old pattern (`user.mollie_customer&.subscriptions&.active&.exists?`) vs the new (`user.mollie_subscriptions.active.exists?`)
- [ ] **Billing dashboard improvements**: Show how `mollie_payments` is now a real association that supports chaining:
  ```ruby
  @payments = Current.user.mollie_payments.order(created_at: :desc).limit(10)
  ```
- [ ] **Eager loading for admin views**: Document `includes(mollie_customer: :subscriptions)` pattern for loading multiple users with their subscriptions
- [ ] **Available scopes**: List all chainable scopes on each association:
  - `mollie_subscriptions`: `.active`, `.pending`, `.canceled`, `.suspended`, `.completed`
  - `mollie_payments`: `.paid`, `.failed`, `.open`, `.recurring`, `.first_payments`
  - `mollie_mandates`: `.valid_status`, `.pending`

### 3.3 New Tutorial Section: Idempotency and Webhook Safety

**File:** `docs/tutorial.md` — Add as "Part 8: Production hardening"

- [ ] **Idempotency guard on first payment callback**: Explain the `return if mollie_subscribed?` guard and why it's essential — webhook retries (`ProcessWebhookJob` retries 5 times) can create duplicate Mollie subscriptions without it
- [ ] **Webhook deduplication**: Explain how MolliePay v0.2 uses a unique index on `mollie_id` to prevent duplicate event processing. Contrast with the old check-then-insert pattern and its race condition.
- [ ] **Error handling patterns**: Show the `rescue Mollie::RequestError, MolliePay::ConfigurationError` pattern for all controllers that call Mollie
- [ ] **Turbo Drive and external redirects**: Remind about `data: { turbo: false }` on forms that redirect to Mollie checkout (cross-origin redirect issue with Turbo)

### 3.4 Update Existing Tutorial Sections

**File:** `docs/tutorial.md`

- [ ] **Part 3 (Subscriptions)**: Update `SubscriptionSetupsController` code to show the `method:` parameter being used (even if the basic tutorial uses a simpler version, mention it)
- [ ] **Part 3 (Subscriptions)**: Update `on_mollie_first_payment_paid` to include the idempotency guard
- [ ] **Part 3 (Subscriptions)**: Update `subscribe_to_plan!` to show the `start_date:` parameter
- [ ] **Part 4 (Billing dashboard)**: Note that `mollie_payments` is now a through association, not a manual method
- [ ] **Going Further section**: Replace the brief bullet points with links to the new Parts 6-8

---

## Part 4: Test Helper Updates

### 4.1 Update `MolliePay::TestHelper`

**File:** `lib/mollie_pay/test_helper.rb`

- [ ] **`fake_mollie_payment`**: Add `subscription_id: nil` to the default attributes so host apps can test payment-subscription linking
- [ ] **`stub_mollie_subscription_create`**: Accept `start_date:` parameter for testing credit card flows
- [ ] **`webmock_mollie_subscription_create`**: Accept `start_date:` in the request body matching
- [ ] **Document in README**: Add examples of testing payment method selection flows

### 4.2 Add New Test Helpers

- [ ] **`fake_mollie_subscription_with_start_date`**: Convenience for testing deferred-start subscriptions
- [ ] **`webmock_mollie_payment_create_with_method`**: Stub that validates the `method` parameter is passed correctly

---

## Part 5: GitHub Issues to Close/Update

### Issues to reference in PR

- [ ] PR #17 covers: through associations, payment linking, webhook dedup
- [ ] Update issue #18 (named subscriptions) with note that through associations are now shipped, making named subs easier to add later
- [ ] Update issue #19 (metadata pass-through) with note about the credit card first-payment pattern as an alternative approach

---

## Acceptance Criteria

### Documentation
- [ ] README.md updated with all v0.2 changes
- [ ] AGENTS.md updated with new Billable signature and patterns
- [ ] STYLE.md updated with webhook dedup convention
- [ ] CHANGELOG.md created with full v0.2 changelog
- [ ] Tutorial extended with Parts 6 (payment methods), 7 (through associations), 8 (production hardening)
- [ ] Existing tutorial parts updated with idempotency guard and start_date

### Code
- [ ] Test helpers updated for new parameters
- [ ] All gem tests pass
- [ ] Tutorial code examples verified against actual implementation

### Release
- [ ] Version bumped to 0.2.0 in `lib/mollie_pay/version.rb`
- [ ] All acceptance criteria checked off
- [ ] Feature branch merged to master

---

## Implementation Order

1. **CHANGELOG.md** — Create first, establishes what changed
2. **README.md** — Core reference documentation
3. **AGENTS.md + STYLE.md** — Contributor docs
4. **Tutorial Parts 6-8** — New advanced sections
5. **Tutorial existing parts** — Update with guards and new params
6. **Test helper updates** — Code changes
7. **Version bump** — Last step before merge
