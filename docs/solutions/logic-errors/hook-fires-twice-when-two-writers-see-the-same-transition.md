---
title: "A hook fires twice when two writers see the same status transition"
date: 2026-11-25
category: logic-errors
module: MolliePay Mandate, RefreshPendingMandateJob
problem_type: logic_error
component: payments
symptoms:
  - "on_mollie_mandate_created called twice for one mandate"
  - "A stale pending answer from Mollie overwrote a stored valid mandate"
root_cause: concurrency
resolution_type: code_fix
severity: high
tags:
  - hooks
  - idempotency
  - concurrency
  - conditional-update
  - sqlite
  - mandates
---

# A hook fires twice when two writers see the same status transition

## Problem

The engine decides whether to call an `on_mollie_*` hook by comparing a status read into memory with the status it is about to store. That holds while one job writes a record. When the refresh for pending mandates (issue #136) added `RefreshPendingMandateJob` as a second writer, it and a replayed payment webhook could both read the mandate as `pending`, both store Mollie's `valid`, and both call `on_mollie_mandate_created`. The docs tell hosts to subscribe from that hook, so a double call can create two Mollie subscriptions.

A second symptom from the same cause: a refresh that fetched the mandate while it was `pending` could store that answer after the webhook had already stored `valid`, putting the mandate back to `pending`.

## Root cause

`Mandate.record_from_mollie_mandate` read `was_valid = mandate.valid_status?`, called `update!`, and fired the hook when the new status was valid and `was_valid` was false. Two writers that loaded the row before either saved both see `was_valid == false`. A row lock does not help on the dummy app's SQLite: SQLite has no row-level locks, so `lock!` does not serialize the two writers.

## Solution

Let the database decide who made the transition. `Mandate#record_status` moves the row to `valid` with one conditional `UPDATE` and fires the hook only when that statement changed a row:

```ruby
unsettled = self.class.where(id: id).where.not(status: "valid")
became_valid = unsettled.update_all([ "status = ?, mandated_at = COALESCE(mandated_at, ?), updated_at = ?", "valid", now, now ]) == 1
```

A `pending` answer goes through the same `where.not(status: "valid")` scope, so it can no longer replace `valid`. Mollie never takes a valid mandate back to pending. `COALESCE` keeps `mandated_at` set once. Two tests in `test/models/mollie_pay/mandate_test.rb` pin both behaviours.

## Prevention

- Before adding a second job, retry path or callback that writes a record whose status drives a hook, check how the hook decides it fired. An in-memory "previous status" comparison is only safe with a single writer.
- `Payment.record_from_mollie`, `Subscription.record_from_mollie`, `Refund.record_from_mollie` and `SalesInvoice.record_from_mollie` still use an in-memory `previous_status`. Today their only writer is the webhook job, but Mollie can deliver the same webhook twice and a queue can run both at once. If one of them gains a second writer, move its transition to a conditional `update_all` the same way.
- Do not reach for `lock!` to fix this in the engine. It is a no-op on SQLite.

## Related Issues

- GitHub issue #136
- GitHub issue #141, which changes how hooks are called after a status is saved
