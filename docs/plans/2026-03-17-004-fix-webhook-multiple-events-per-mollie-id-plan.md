---
title: "fix: Allow multiple webhook events per mollie_id"
type: fix
status: completed
date: 2026-03-17
---

# fix: Allow multiple webhook events per mollie_id

## Enhancement Summary

**Deepened on:** 2026-03-17
**Review agents used:** architecture-strategist, data-integrity-guardian, data-migration-expert,
dhh-rails-reviewer, kieran-rails-reviewer, security-sentinel, performance-oracle,
code-simplicity-reviewer, pattern-recognition-specialist, deployment-verification-agent

### Key Improvements From Review
1. Migration uses explicit `up`/`down` instead of `change` — rollback requires dedup SQL
2. Add `rescue RecordNotUnique` to `Payment.record_from_mollie` and `Refund.record_from_mollie` — closes concurrent INSERT race that Subscription already handles
3. Add `discard_on ActiveRecord::RecordNotFound` to ProcessWebhookJob — prevents 5x retry amplification for fabricated `sub_`/`re_` IDs
4. Drop the `mollie_id` index entirely — no code path queries `webhook_events` by `mollie_id`
5. Update STYLE.md and docs/tutorial.md (originally missed)
6. Document that host app hooks should be idempotent (at-least-once delivery semantics)

### Dissenting View (DHH Reviewer)
The DHH reviewer argued the unique index is correct because `WebhookEvent` is a receipt,
not an audit log, and `record_from_mollie` always fetches current state. The rebuttal:
if the second webhook is silently dropped at the controller, **no job is ever enqueued**
to fetch the current state. The payment stays stuck at its first-observed status.

---

## Overview

Mollie sends multiple webhooks with the **same resource ID** for legitimate status
transitions (e.g., `tr_abc123` for `authorized`, then again for `paid`). The current
unique index on `mollie_pay_webhook_events.mollie_id` silently drops these subsequent
webhooks via `RecordNotUnique` rescue, meaning status transitions after the first
webhook are **never processed**.

This is a correctness bug: payments can get stuck in intermediate states because
later status-change webhooks are discarded at the database level.

## Problem Statement / Motivation

### How Mollie webhooks work

Mollie sends a POST with only `id=tr_abc123` — no status, no payload. The
application must fetch the current state from the Mollie API. Webhooks fire for
these statuses:

| Status | Webhook? |
|------------|----------|
| open | No |
| pending | No |
| authorized | Yes |
| paid | Yes |
| failed | Yes |
| canceled | Yes |
| expired | Yes |

A payment transitioning `open → authorized → paid` receives **two** webhooks,
both with `id=tr_abc123`. This is expected, documented behavior.

Additionally, Mollie retries webhooks up to 10 times over 26 hours if it does not
receive HTTP 200.

Sources:
- [Mollie Webhooks Reference](https://docs.mollie.com/reference/webhooks)
- [Handling Payment Status](https://docs.mollie.com/docs/handling-payment-status)

### Current behavior (bug)

```
Webhook 1: POST { id: "tr_abc123" }  →  WebhookEvent created  →  Job processes "authorized"  ✓
Webhook 2: POST { id: "tr_abc123" }  →  RecordNotUnique        →  head :ok (DROPPED)         ✗
```

The payment stays `authorized` forever. The `paid` webhook is silently ignored.

### Desired behavior

```
Webhook 1: POST { id: "tr_abc123" }  →  WebhookEvent #1 created  →  Job fetches "authorized"  ✓
Webhook 2: POST { id: "tr_abc123" }  →  WebhookEvent #2 created  →  Job fetches "paid"        ✓
```

Each webhook creates a new event row and gets its own job. The existing model-level
idempotency (`find_or_initialize_by` + `previous_status` check) handles deduplication
correctly — hooks fire only on actual status transitions.

## Proposed Solution

### Migration: Drop the unique index entirely

No code path queries `webhook_events` by `mollie_id` — the job uses primary key
(`WebhookEvent.find(event_id)`). The index is dead weight. Use explicit `up`/`down`
because rollback requires deduplication SQL if duplicate rows exist.

```ruby
# db/migrate/YYYYMMDDHHMMSS_remove_unique_constraint_from_webhook_event_mollie_id.rb
class RemoveUniqueConstraintFromWebhookEventMollieId < ActiveRecord::Migration[8.1]
  def up
    remove_index :mollie_pay_webhook_events,
                 name: "index_mollie_pay_webhook_events_on_mollie_id"
  end

  def down
    # Remove duplicates before restoring unique index — keep oldest per mollie_id
    execute <<~SQL
      DELETE FROM mollie_pay_webhook_events
      WHERE id NOT IN (
        SELECT MIN(id) FROM mollie_pay_webhook_events GROUP BY mollie_id
      )
    SQL

    add_index :mollie_pay_webhook_events, :mollie_id,
              unique: true,
              name: "index_mollie_pay_webhook_events_on_mollie_id"
  end
end
```

### Controller: Remove RecordNotUnique rescue

```ruby
# app/controllers/mollie_pay/webhooks_controller.rb
module MolliePay
  class WebhooksController < ApplicationController
    skip_forgery_protection

    def create
      mollie_id = params.expect(:id)

      event = WebhookEvent.create!(mollie_id: mollie_id)
      ProcessWebhookJob.perform_later(event.id)

      head :ok
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid
      head :unprocessable_entity
    end
  end
end
```

### Payment & Refund: Add RecordNotUnique rescue (consistency fix)

`Subscription.record_from_mollie` already rescues `RecordNotUnique` (line 45) for
its partial unique index on `[customer_id, name]`. With multiple webhook events per
`mollie_id`, two concurrent jobs can race on the first INSERT for a new Payment or
Refund record. Add the same rescue pattern for consistency:

```ruby
# In Payment.record_from_mollie — after find_or_initialize_by + update!
rescue ActiveRecord::RecordNotUnique
  find_by!(mollie_id: mp.id)
```

Same pattern for `Refund.record_from_mollie`.

### ProcessWebhookJob: Add discard_on RecordNotFound

`fetch_subscription_from_mollie` and `fetch_refund_from_mollie` do
`Subscription.find_by!` / `Refund.find_by!` which raise `ActiveRecord::RecordNotFound`
for locally unknown IDs. Currently this triggers 5 retry attempts (via `retry_on
StandardError`) that can never succeed. Add:

```ruby
discard_on ActiveRecord::RecordNotFound
```

## Technical Considerations

### Why model-level idempotency is sufficient

The `record_from_mollie` pattern on Payment, Subscription, and Refund already:

1. Uses `find_or_initialize_by(mollie_id:)` + `update!` (upsert)
2. Tracks `previous_status` before update
3. Fires hooks **only when** `status != previous_status`
4. Sets transition timestamps once, never overwrites

This means:
- Two jobs for the same `mollie_id` with the same status → second is a no-op
- Two jobs for the same `mollie_id` with different statuses → both update, hook
  fires only on the transition

### Why Mollie API fetch eliminates ordering concerns

Since Mollie only sends an `id` (no status), the job **always fetches current
state** from the Mollie API. If webhooks arrive out of order, both jobs fetch the
same current state. The `previous_status` check ensures the hook fires exactly once.

### Concurrent first-INSERT race

If two jobs for the same `mollie_id` race on creating a **new** local record (both
call `find_or_initialize_by` before either inserts), one INSERT succeeds and the
other raises `RecordNotUnique` on the model's unique `mollie_id` index. The rescue
falls back to `find_by!` and the job proceeds as an update. This is the same pattern
Subscription already uses.

### Hook delivery semantics: at-least-once

With multiple webhook events per `mollie_id`, hooks have **at-least-once** delivery
semantics rather than exactly-once. In the common case, `previous_status` checks
prevent duplicate hook calls. In the rare concurrent-INSERT race (both jobs read
`previous_status = nil`), a hook could fire twice.

Host app hooks should be implemented **idempotently** — this is already good practice
and will be documented in the README.

### Table growth

Without the index, each webhook delivery creates a row. Growth is proportional to
actual status changes (typically 2-3 per payment lifecycle). If the app is temporarily
unavailable, Mollie retries up to 10 times per webhook — bounded and self-limiting.

### Performance impact

| Dimension | Current | After | Notes |
|-----------|---------|-------|-------|
| webhook_events rows/payment | 1 | 2-3 | Linear, small rows |
| Jobs/payment | 1 | 2-3 | Lightweight (1 API call + 1 upsert) |
| Mollie API calls/payment | 1 | 2-3 | Well within rate limits (500/5s) |

Acceptable tradeoff for correctness. The Mollie API calls are the main cost.

## System-Wide Impact

- **Interaction graph**: Controller → WebhookEvent.create! → ProcessWebhookJob →
  event.process! → Model.record_from_mollie → billable hooks. No change to the
  chain, only the controller-level gate is removed.
- **Error propagation**: Improved — `discard_on RecordNotFound` prevents wasteful
  retries for unknown sub_/re_ IDs.
- **State lifecycle risks**: Concurrent INSERT race closed by `RecordNotUnique`
  rescue in Payment and Refund (matching existing Subscription pattern).
- **API surface parity**: No public API changes. Host app code is unaffected.

### Deployment order for host apps

**Migration first, then code deploy** (recommended). Between steps, the old code's
`RecordNotUnique` rescue becomes dead code — harmless, since the constraint is gone
and duplicates are handled idempotently by the model layer.

**Code first, then migration** (not recommended). The `RecordNotUnique` rescue is
removed but the unique index still exists — duplicate webhooks return 500 to Mollie.
Mollie retries, so no data loss, but noisy error logs.

## Acceptance Criteria

- [ ] New migration drops unique index on `mollie_pay_webhook_events.mollie_id`
      (no replacement index needed)
- [ ] Migration `down` deduplicates rows before restoring unique index
- [ ] Controller no longer rescues `ActiveRecord::RecordNotUnique`
- [ ] `Payment.record_from_mollie` rescues `RecordNotUnique` (matching Subscription)
- [ ] `Refund.record_from_mollie` rescues `RecordNotUnique` (matching Subscription)
- [ ] `ProcessWebhookJob` adds `discard_on ActiveRecord::RecordNotFound`
- [ ] Multiple webhooks with the same `mollie_id` each create a separate
      `WebhookEvent` row and enqueue a job
- [ ] Status transitions are processed correctly (authorized → paid)
- [ ] True duplicate webhooks (same status) are handled idempotently at the model level
- [ ] AGENTS.md updated to document new pattern and rationale
- [ ] STYLE.md updated (webhook deduplication section, lines 274-290)
- [ ] README.md updated (webhook section, hook idempotency note, upgrading section)
- [ ] docs/tutorial.md updated (webhook deduplication section, lines 1217-1236)
- [ ] CHANGELOG.md updated with v0.4.0 entry
- [ ] All existing tests pass, new tests cover multi-event scenarios

## Implementation Plan

### Phase 1: Migration + Code (single PR)

**Files to change:**

1. `db/migrate/YYYYMMDDHHMMSS_remove_unique_constraint_from_webhook_event_mollie_id.rb` — new migration (up/down)
2. `app/controllers/mollie_pay/webhooks_controller.rb` — remove `RecordNotUnique` rescue
3. `app/models/mollie_pay/payment.rb` — add `rescue RecordNotUnique` in `record_from_mollie`
4. `app/models/mollie_pay/refund.rb` — add `rescue RecordNotUnique` in `record_from_mollie`
5. `app/jobs/mollie_pay/process_webhook_job.rb` — add `discard_on ActiveRecord::RecordNotFound`
6. `test/dummy/db/schema.rb` — regenerated (index removed)

**Tests to change:**

7. `test/controllers/mollie_pay/webhooks_controller_test.rb` — replace dedup tests:
   - Replace "deduplicates already-received webhook events" → same mollie_id creates
     multiple events and enqueues multiple jobs
   - Replace "deduplicates already-processed webhook events" → same mollie_id creates
     new event even if prior event was processed
   - Keep "rejects missing id" and "rejects invalid format" tests
8. `test/jobs/mollie_pay/process_webhook_job_test.rb` — add test for RecordNotFound discard
9. `test/models/mollie_pay/payment_test.rb` — add test for concurrent RecordNotUnique rescue

### Phase 2: Documentation

10. `AGENTS.md` — update webhook deduplication section (lines ~97-100)
11. `STYLE.md` — update webhook deduplication section (lines 274-290)
12. `README.md` — update webhook section, add hook idempotency note, add "Upgrading to v0.4"
13. `docs/tutorial.md` — update webhook deduplication section (lines 1217-1236)
14. `CHANGELOG.md` — add v0.4.0 entry under "Fixed"

### Test cases to add/modify

| Test | File | Description |
|------|------|-------------|
| Replace | `webhooks_controller_test.rb:19` | Same mollie_id creates multiple events |
| Replace | `webhooks_controller_test.rb:30` | Same mollie_id creates event even if prior processed |
| New | `webhooks_controller_test.rb` | Each event enqueues its own job |
| New | `process_webhook_job_test.rb` | RecordNotFound is discarded (no retry) |
| New | `payment_test.rb` | Concurrent record_from_mollie with RecordNotUnique rescue |
| Existing | `process_webhook_job_test.rb` | "skips already processed events" — still valid |
| Existing | `webhook_event_test.rb` | process!/scopes tests — still valid |
