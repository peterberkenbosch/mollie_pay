---
title: "feat: Add subscription plan swap (upgrade/downgrade)"
type: feat
status: completed
date: 2026-03-22
github_issue: 66
---

# feat: Add subscription plan swap (upgrade/downgrade)

## Overview

Add the ability to change a customer's subscription plan — upgrading or
downgrading by modifying the amount, interval, and/or description on an
existing subscription. Uses the Mollie Update Subscription API (`PATCH`)
for in-place changes. No cancel-and-recreate needed.

## Problem Statement

A customer on subscription plan A needs to move to plan B (different amount,
interval, or description). Currently the only option is to cancel and
resubscribe, which creates a gap where `mollie_subscribed?` returns `false`
and the partial unique index blocks concurrent creation for the same name.

## Proposed Solution

Add `mollie_swap_subscription` to the Billable concern that PATCHes the
existing subscription on Mollie, then updates the local record to match.

### Why PATCH, not cancel-and-recreate

**Verified against the live Mollie API:** The `PATCH /v2/customers/{id}/subscriptions/{id}`
endpoint accepts `amount`, `interval`, `description`, `times`, `startDate`,
`webhookUrl`, `mandateId`, and `metadata`. This was tested against the live API
on 2026-03-22 — interval changes are accepted via PATCH.

This eliminates the need for cancel-and-recreate, which would introduce:
- A gap period where `mollie_subscribed?` returns `false`
- Partial unique index conflicts
- Partial failure scenarios (canceled but not recreated)
- Misleading `on_mollie_subscription_canceled` hooks firing during upgrades

### API Design

```ruby
# Change amount only (keeps current interval)
org.mollie_swap_subscription(amount: 4999)

# Change amount and interval
org.mollie_swap_subscription(amount: 4999, interval: "1 year")

# Named subscription
org.mollie_swap_subscription(name: "analytics_addon", amount: 1999)
```

**Parameters:**
- `name:` — subscription name (default: `"default"`)
- `amount:` — new amount in cents (optional, keeps current if nil)
- `interval:` — new interval string (optional, keeps current if nil)
All parameters are optional except at least one of `amount` or `interval`
must be provided (otherwise it's a no-op). Description is managed on the
Mollie dashboard — not accepted as a parameter here, since there is no local
`description` column and silently PATCHing Mollie without local persistence
would be confusing for callers.

### Behavior

1. Find active or pending subscription for the given `name` (uses `ACTIVE_STATUSES` scope)
2. Raise `SubscriptionNotFound` if no active/pending subscription exists
3. Skip API call if nothing actually changed (no-op guard)
4. PATCH the subscription on Mollie via `Mollie::Customer::Subscription.update`
5. Update the local record with new `amount` and `interval`
6. Fire `on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:)`
   hook on the Billable owner
7. Return the updated subscription

### No proration

Mollie does not calculate proration. The new amount/interval takes effect on
the next billing cycle. If the host app needs proration (e.g., charge the
upgrade difference immediately), they can use the
`on_mollie_subscription_swapped` hook to create a one-off payment via
`mollie_pay_once` for the prorated difference.

## Technical Approach

### Files to change

| File | Change |
|------|--------|
| `app/models/mollie_pay/billable.rb` | Add `mollie_swap_subscription` method |
| `app/models/mollie_pay/billable.rb` | Add `on_mollie_subscription_swapped` hook |
| `lib/mollie_pay/test_helper.rb` | Add `stub_mollie_subscription_update` |
| `test/models/mollie_pay/billable_test.rb` | Tests for swap |
| `AGENTS.md` | Document new method and hook |
| `docs/api.md` | Document swap API and proration guidance |

### No migration needed

The `amount` and `interval` columns already exist on `mollie_pay_subscriptions`.
`Subscription.record_from_mollie` already syncs both from Mollie webhooks.
No `description` column is added — description is Mollie-side only, matching
the existing pattern.

### Implementation

```ruby
# app/models/mollie_pay/billable.rb

def mollie_swap_subscription(name: "default", amount: nil, interval: nil)
  subscription = mollie_subscriptions.where(status: Subscription::ACTIVE_STATUSES).named(name).first
  raise MolliePay::SubscriptionNotFound, "No active subscription" unless subscription

  params = {}
  params[:amount]   = mollie_amount(amount) if amount && amount != subscription.amount
  params[:interval] = interval              if interval && interval != subscription.interval
  return subscription if params.empty?

  previous_amount   = subscription.amount
  previous_interval = subscription.interval

  Mollie::Customer::Subscription.update(
    subscription.mollie_id,
    customer_id: mollie_customer.mollie_id,
    **params
  )

  subscription.update!(
    amount:   amount || subscription.amount,
    interval: interval || subscription.interval
  )

  on_mollie_subscription_swapped(
    subscription,
    previous_amount: previous_amount,
    previous_interval: previous_interval
  )

  subscription
end
```

### Hook

```ruby
# New no-op hook in Billable
def on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:) ; end
```

The hook receives the updated subscription plus the previous values, enabling
the host app to calculate proration if needed:

```ruby
# Host app example
def on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:)
  if subscription.amount > previous_amount
    difference = subscription.amount - previous_amount
    mollie_pay_once(
      amount: difference,
      description: "Upgrade proration",
      redirect_url: billing_url
    )
  end
end
```

### Test helper

```ruby
# lib/mollie_pay/test_helper.rb

def stub_mollie_subscription_update(**overrides, &block)
  response = fake_mollie_subscription(**overrides)
  Mollie::Customer::Subscription.stub(:update, response, &block)
end
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Swap to same amount/interval | No-op, returns subscription without API call |
| No active subscription | Raises `SubscriptionNotFound` |
| Suspended subscription | Not found (scope uses `ACTIVE_STATUSES`), raises `SubscriptionNotFound` |
| Pending subscription | Found (included in `ACTIVE_STATUSES`), PATCH sent to Mollie |
| Canceled subscription | Not found, raises `SubscriptionNotFound` |
| Mollie API error | Raises Mollie error, local record unchanged |
| Webhook arrives after swap | `record_from_mollie` syncs amount/interval from Mollie — consistent |
| Concurrent swap requests | Last PATCH wins on Mollie side; local record updated by each caller |

### Suspended subscription consideration

A suspended subscription cannot be swapped because the scope only finds
`active` subscriptions. This is intentional — a suspended subscription has
payment issues that should be resolved before changing the plan. Document
this limitation.

## Acceptance Criteria

- [ ] `mollie_swap_subscription(amount:)` updates amount on active subscription
- [ ] `mollie_swap_subscription(interval:)` updates interval on active subscription
- [ ] `mollie_swap_subscription(amount:, interval:)` updates both fields
- [ ] Only changed values are sent to Mollie API (partial PATCH)
- [ ] No-op when called with same values as current subscription
- [ ] Swaps pending subscriptions (included in `ACTIVE_STATUSES`)
- [ ] Raises `SubscriptionNotFound` when no active/pending subscription for name
- [ ] Local `amount` and `interval` columns updated after successful PATCH
- [ ] `on_mollie_subscription_swapped` hook fires with previous values
- [ ] Named subscriptions work: `mollie_swap_subscription(name: "addon", amount: 1999)`
- [ ] `stub_mollie_subscription_update` test helper added
- [ ] AGENTS.md updated with new method and hook
- [ ] docs/api.md updated with swap API and proration guidance

## Sources & References

- Mollie Update Subscription API: https://docs.mollie.com/reference/update-subscription
- Mollie SDK: `Mollie::Customer::Subscription.update` (inherits from `Mollie::Base.update`)
- Live API verification: PATCH with `interval` confirmed working on 2026-03-22
- Named subscriptions plan: `docs/plans/2026-03-17-003-feat-named-subscriptions-plan.md`
- Pay gem swap pattern: https://github.com/pay-rails/pay
- Laravel Cashier proration: https://laravel.com/docs/11.x/billing
- Existing patterns: `app/models/mollie_pay/billable.rb` (mollie_subscribe, mollie_cancel_subscription)
