---
title: "Implement Chargeback model with correct Mollie webhook detection and SDK compatibility"
category: integration-issues
date: 2026-03-22
tags:
  - chargebacks
  - webhooks
  - mollie-api
  - sdk-compatibility
  - payment-lifecycle
  - record-not-unique
  - test-fixtures
severity: high
components:
  - Payment model
  - Chargeback model
  - Billable concern
  - TestHelper
related:
  - docs/plans/2026-03-21-001-feat-chargeback-model-webhook-detection-plan.md
  - "GitHub issue #47"
  - "GitHub PR #58"
---

# Chargeback Model: Mollie API Discovery and SDK Workarounds

## Problem

Chargebacks were completely invisible in the mollie_pay engine. Mollie does
NOT send separate chargeback webhooks — chargebacks arrive embedded in the
payment object via `tr_` webhooks, with `amountChargedBack` changing while
payment status stays "paid". The existing `previous_status` detection pattern
was blind to this. Additionally, the `mollie-api-ruby` SDK does not expose
all API fields, and its test fixtures don't match real API responses.

## Root Cause

Three interacting problems:

1. **No dedicated chargeback webhook.** Detection requires comparing
   `amount_charged_back` before and after updating the payment record — the
   `previous_status` pattern does not apply.

2. **Undocumented SDK gaps.** The Mollie API returns chargeback `reason` as
   a nested object (`{"code": "AM04", "description": "Insufficient funds"}`),
   but `mollie-api-ruby`'s `Chargeback` class has no `attr_accessor :reason`.
   The data is only accessible via `mc.attributes["reason"]` because
   `Mollie::Base` stores the full parsed response hash.

3. **SDK key conversion affects fixtures.** The gem's `Util.nested_underscore_keys`
   converts all JSON keys from camelCase to snake_case. Test fixtures must use
   camelCase (matching the real API), not snake_case. The gem's own test fixture
   (`get_embedded_resources.json`) uses snake_case and lacks `reason` — it does
   not match current live API behavior.

## Solution

### 1. Amount-based detection in Payment.record_from_mollie

```ruby
previous_amount_charged_back = payment.amount_charged_back
payment.update!(...)
Chargeback.sync_for_payment(payment) if payment.amount_charged_back != previous_amount_charged_back
```

### 2. Reason extraction via raw attributes hash

The SDK stores all parsed response data in `@attributes`, even for fields
without `attr_accessor`. Access `reason` through the hash:

```ruby
def self.extract_reason(mollie_chargeback)
  reason = (mollie_chargeback.try(:attributes) || {})["reason"]
  return nil if reason.nil?

  if reason.is_a?(Hash)
    description = reason["description"]
    code        = reason["code"]
    code ? "#{description} (#{code})" : description
  else
    reason.to_s
  end
end
```

### 3. Per-chargeback RecordNotUnique with deferred hook dispatch

The initial implementation wrapped `rescue RecordNotUnique` + `retry` around
the entire sync loop — this created an infinite loop risk and re-fired hooks
for already-processed chargebacks. Fix: rescue inside the loop with `find_by!`
fallback, and accumulate events for dispatch after all records are persisted.

```ruby
def self.sync_for_payment(payment)
  mollie_chargebacks = payment.mollie_record.chargebacks
  return if mollie_chargebacks.blank?

  billable = payment.customer.owner
  events = []

  mollie_chargebacks.each do |mc|
    chargeback = find_or_initialize_by(mollie_id: mc.id)
    was_new = chargeback.new_record?
    was_reversed = chargeback.reversed_at

    chargeback.update!(
      payment:           payment,
      amount:            mollie_value_to_cents(mc.amount),
      currency:          mc.amount.currency,
      reason:            extract_reason(mc),
      created_at_mollie: mc.created_at,
      reversed_at:       mc.reversed_at
    )

    if was_new
      events << [ :received, chargeback ]
    elsif chargeback.reversed_at.present? && was_reversed.nil?
      events << [ :reversed, chargeback ]
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(mollie_id: mc.id)
  end

  events.each do |type, chargeback|
    case type
    when :received then billable.on_mollie_chargeback_received(chargeback)
    when :reversed then billable.on_mollie_chargeback_reversed(chargeback)
    end
  end
end
```

### 4. Test fixtures must match real API responses

The Mollie API returns camelCase keys. The SDK converts them to snake_case
internally. Fixtures should use camelCase:

```json
{
  "resource": "chargeback",
  "id": "chb_ls7ahg",
  "amount": { "value": "10.00", "currency": "EUR" },
  "createdAt": "2026-01-03T13:20:37+00:00",
  "reason": { "code": "AM04", "description": "Insufficient funds" },
  "paymentId": "tr_test1234AB",
  "settlementAmount": { "value": "-10.00", "currency": "EUR" }
}
```

**Do not** copy the gem's own test fixtures as ground truth — they may use
snake_case keys and lack fields present in the real API.

## Investigation Steps

1. Checked the Mollie API docs and confirmed no separate chargeback webhook exists
2. Implemented amount_charged_back comparison in `Payment.record_from_mollie`
3. Built `Chargeback.sync_for_payment` following the Refund model pattern
4. Code review caught the `rescue RecordNotUnique` + `retry` infinite loop risk
5. Discovered SDK doesn't expose `reason` — verified by fetching live API data
   from `GET /v2/payments/{id}/chargebacks/{id}` which returned
   `"reason": {"code": "AM04", "description": "Insufficient funds"}`
6. Found that `Mollie::Base#attributes` stores the full response hash
7. Discovered SDK converts camelCase → snake_case via `Util.nested_underscore_keys`
8. Updated fixtures to use camelCase matching real API responses

## Prevention

### When adding new Mollie resource models

1. **Always fetch live API data first.** Before designing a model, call the real
   API and inspect the raw JSON. Don't rely solely on SDK class definitions or
   gem test fixtures.

2. **Check `mc.attributes` for hidden fields.** The SDK may not expose all API
   fields via `attr_accessor`. The raw `attributes` hash is the complete picture.

3. **Use camelCase in JSON test fixtures.** The SDK handles the conversion.
   Snake_case fixtures skip the conversion path and can mask bugs.

4. **Classify the detection pattern.** Not all Mollie events use status transitions.
   Ask: "What field(s) change when this event occurs?" For chargebacks it's
   `amount_charged_back`, not `status`.

### When using RecordNotUnique rescue

1. **Never wrap an entire loop in `rescue RecordNotUnique` + `retry`.** This
   re-processes already-handled items and can loop infinitely.

2. **Rescue per-item with `find_by!` fallback.** Matches the existing Payment
   and Refund patterns in this codebase.

3. **Separate persistence from hook dispatch.** Accumulate events during the
   persistence loop, dispatch after all records are saved. This prevents lost
   notifications on partial failure.

## Related

- [Plan: Chargeback model](../../plans/2026-03-21-001-feat-chargeback-model-webhook-detection-plan.md)
- GitHub issue: #47
- GitHub PR: #58
- Refund model (`app/models/mollie_pay/refund.rb`) — template for the Chargeback pattern
- `Mollie::Base#attributes` — raw response hash in mollie-api-ruby
- `Mollie::Util.nested_underscore_keys` — camelCase → snake_case conversion
