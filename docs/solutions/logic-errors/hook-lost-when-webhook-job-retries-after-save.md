---
title: "A hook that raised is never called again when the webhook job retries"
date: 2026-11-25
category: logic-errors
module: MolliePay ProcessWebhookJob, NotifyBillableJob
problem_type: logic_error
component: payments
symptoms:
  - "An on_mollie_* hook raised once and was never called again"
  - "The local record shows the new status, but the host app never reacted to it"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags:
  - hooks
  - idempotency
  - activejob
  - retry-on
  - globalid
  - testing
---

# A hook that raised is never called again when the webhook job retries

## Problem

`record_from_mollie` saved the new status and then called the host's
`on_mollie_*` hook inline. When the hook raised, `ProcessWebhookJob` retried.
The retry fetched the object from Mollie again, saw the stored status already
equal to Mollie's, found no transition, and skipped the hook. Issue #141.

## Root cause

The hook is gated on "status changed", and the change was already committed
before the hook ran. Retrying the job that made the change cannot replay a
side effect that depends on the change not having happened yet.

## Solution

Each hook runs in its own `MolliePay::NotifyBillableJob`
(`app/jobs/mollie_pay/notify_billable_job.rb`), enqueued after the save. That
job owns the retry for the hook, so hooks are at-least-once and must be
idempotent. Fix pending in the #141 pull request.

```ruby
NotifyBillableJob.perform_later(billable, hook, self) if hook
```

The regression test is `test/jobs/mollie_pay/process_webhook_job_test.rb`,
"a hook that raised is called again when it is retried".

## Testing traps found on the way

- `perform_enqueued_jobs` without a block flushes the queue once and does not
  run the retries `retry_on` schedules. Use the block form,
  `perform_enqueued_jobs { ProcessWebhookJob.perform_now(id) }`, to see a
  retried hook run.
- A hook stubbed with `define_singleton_method` on the owner instance is lost:
  the owner is serialized through GlobalID and the job loads a fresh instance.
  Either define the hook on the class (`Organization.define_method`, removed in
  `ensure`), or assert the enqueue:
  `assert_enqueued_with job: NotifyBillableJob, args: [ owner, :hook, record ]`.

## Prevention

When a side effect is gated on a state change, do not run it in the same
retry unit as the write that records the change. Give it its own job, or the
first failure loses it.
