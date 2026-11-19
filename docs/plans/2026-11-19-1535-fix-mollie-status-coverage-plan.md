---
title: Mollie Status Coverage for Sales Invoices and Refunds - Plan
type: fix
date: 2026-11-19
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# Mollie Status Coverage for Sales Invoices and Refunds - Plan

## Goal Capsule

- **Objective:** A host app can store any sales invoice or refund that Mollie returns today without the engine raising, for every status in Mollie's current enums.
- **Authority:** This plan, then `AGENTS.md`, then Mollie's OpenAPI spec at https://github.com/mollie/openapi (`specs.yaml`, commit `199bc3a`, 2026-11-13). When the plan and the spec disagree on a status value, the spec wins.
- **Execution profile:** Rails engine code, Minitest with fixtures, one pull request. No migration, no new gem, no new column.
- **Stop conditions:** Stop and report if a status in R1 or R4 is not in the spec's current enum, or if the change turns out to need a database column or migration.
- **Tail ownership:** The calling pipeline owns simplification, review, commit and PR.

---

## Product Contract

### Summary

`MolliePay::SalesInvoice` and `MolliePay::Refund` accept every status in Mollie's current enums. The sales invoice cancel status takes Mollie's spelling, `cancelled`. Docs and the changelog are updated. Nothing else about invoice or refund behaviour changes.

### Problem Frame

Both models store Mollie's status string verbatim and validate it against a constant. The constants are behind Mollie's API.

For sales invoices the API returns ten statuses and the engine accepts four. One of those four, `canceled`, is not a value Mollie returns at all, because Mollie spells it `cancelled`. `Billable#mollie_create_sales_invoice` calls `SalesInvoice.record_from_mollie` after the invoice already exists at Mollie, so an unlisted status leaves an invoice at Mollie with no local record and an exception in the host app.

For refunds the API returns six statuses and the engine accepts five. A `canceled` refund raises in `Refund.record_from_mollie`. The webhook job reaches that method only for `re_` ids, and whether Mollie posts those is unverified (see Deferred to Follow-Up Work).

Both gaps were confirmed on master at `5da4c31`: `SalesInvoice.new(status: s).valid?` is false for `issuing`, `pending-payment`, `overdue`, `payment-reversed`, `cancelled`, `expired` and `failed`, and `Refund.new(status: "canceled").valid?` is false.

### Requirements

**Sales invoices**

- R1. `MolliePay::SalesInvoice` accepts exactly Mollie's response statuses: `draft`, `issuing`, `issued`, `pending-payment`, `paid`, `overdue`, `payment-reversed`, `cancelled`, `expired`, `failed`.
- R2. `SalesInvoice#canceled?` and `Mollie::SalesInvoice#canceled?` are true for an invoice whose status is `cancelled`.

**Refunds**

- R4. `MolliePay::Refund` accepts exactly Mollie's statuses: `queued`, `pending`, `processing`, `refunded`, `failed`, `canceled`.
- R5. Syncing a `canceled` refund stores the status and does not fire `on_mollie_refund_processed`.

**Documentation**

- R7. `docs/api.md` lists the valid statuses for refunds and sales invoices as the models define them, and the changelog records the fix and the changed `cancelled` value.

### Scope Boundaries

- No cancel-refund operation (issue #80).
- No next-gen webhook syncing of invoices or refunds (issue #98).
- No new sales invoice columns such as `eInvoiceStatus`.
- No new hooks, scopes, predicates or constants for the added statuses.
- No change to the `SalesInvoice.overdue` scope or to the `issued?` guard in `mollie_mark_invoice_paid`. Considered and not built: invoices are synced only at creation, so a local row cannot reach `overdue` or `pending-payment` through the engine. Invoice syncing after creation (issue #98) would change this.
- No change to which transitions fire `on_mollie_sales_invoice_issued` and `on_mollie_sales_invoice_paid`, for the same reason.
- No data migration for stored `canceled` invoice rows. Considered and not built: no engine code path writes that value and no Mollie response contains it. Evidence of a host app with such rows would change this.

#### Deferred to Follow-Up Work

- Verify whether Mollie posts `re_` ids to classic webhooks. If it only posts `tr_` ids, refund status changes never reach `Refund.record_from_mollie` and need a different sync path.
- An invoice whose create response is `issuing` is stored as `issuing` and stays that way locally, because nothing syncs it later. `on_mollie_sales_invoice_issued` does not fire for it and `mollie_mark_invoice_paid` rejects it. Whether Mollie returns `issuing` synchronously on create is unverified. Invoice syncing (issue #98) is the fix.

### Open Questions

- Deferred, does not block this work: Mollie's spec marks its status enums as open (`x-speakeasy-unknown-values: allow`), so a status added later will raise again. Whether the engine should store unknown statuses instead of validating against a fixed list is a design choice across all models, including `Payment`, and is the owner's to make.

---

## Planning Contract

### Key Technical Decisions

- KTD1. **Status constants list Mollie's values verbatim, in the spec's order.** The models already store `mollie_object.status` unchanged, so the constant is the only place that can drift. Implements R1 and R4.
- KTD2. **`STATUS_CANCELED` keeps its name and its value becomes `"cancelled"`.** The same applies to the engine's SDK class `Mollie::SalesInvoice`. Keeping the name leaves host code that references the constant or calls `canceled?` working, and matches Mollie's own event name `sales-invoice.canceled`. An added `STATUS_CANCELLED` beside the old value was rejected because the old value matches nothing Mollie returns. Implements R1 and R2.
- KTD5. **The added sales invoice statuses appear in `STATUSES` as literals, without new constants.** No code branches on them. This keeps the change the size of the defect.

### Assumptions

These were inferred without user confirmation.

- Changing the value of `STATUS_CANCELED` is acceptable before 1.0, and is recorded as a breaking change in the changelog. A host that compares against the literal `"canceled"` must change it.
- No hook is wanted for a `canceled` refund.

### Sources

- Mollie OpenAPI spec, schemas `sales-invoice-status-response`, `sales-invoice-status-update` and `refund-status`.
- `app/models/mollie_pay/sales_invoice.rb`, `app/models/mollie_pay/refund.rb`, `lib/mollie/sales_invoice.rb`, `app/models/mollie_pay/billable.rb` (`mollie_create_sales_invoice`), `app/jobs/mollie_pay/process_webhook_job.rb` (`sync_refund`).
- `docs/solutions/integration-issues/mollie-chargeback-model-api-discovery.md` for the precedent that the SDK and the engine's assumptions can lag the live API.

---

## Implementation Units

### U1. Accept the `canceled` refund status

- **Goal:** A refund Mollie reports as `canceled` is stored instead of raising.
- **Requirements:** R4, R5.
- **Dependencies:** none.
- **Files:** `app/models/mollie_pay/refund.rb`, `test/models/mollie_pay/refund_test.rb`, `test/jobs/mollie_pay/process_webhook_job_test.rb`.
- **Approach:** Add the status to `Refund::STATUSES` per KTD1. `record_from_mollie` needs no other change, because it fires the hook only on a transition to `refunded`.
- **Patterns to follow:** the existing `record_from_mollie` tests in `test/models/mollie_pay/refund_test.rb`.
- **Test scenarios:**
  - A refund with status `canceled` is valid.
  - `Refund.record_from_mollie` with a Mollie refund in status `canceled` updates an existing `queued` refund to `canceled` and leaves `refunded_at` nil.
  - The same sync does not call `on_mollie_refund_processed`.
  - `ProcessWebhookJob.perform_now` with the refund's `re_` id and a Mollie response in status `canceled` completes without raising and stores `canceled`. This seam proves the job no longer retries on this status. It does not prove Mollie posts `re_` ids.
  - A refund with status `nonsense` is still invalid.
- **Verification:** the refund model and webhook job tests pass, including the new scenarios.

### U2. Accept every sales invoice status and fix the cancel spelling

- **Goal:** Every sales invoice status Mollie returns is storable, and the cancel status is spelled as Mollie spells it.
- **Requirements:** R1, R2.
- **Dependencies:** none.
- **Files:** `app/models/mollie_pay/sales_invoice.rb`, `lib/mollie/sales_invoice.rb`, `test/models/mollie_pay/sales_invoice_test.rb`, `test/lib/mollie/sales_invoice_test.rb`, `test/models/mollie_pay/billable_test.rb`.
- **Approach:** Extend `SalesInvoice::STATUSES` per KTD1 and KTD5, and change the cancel constant per KTD2 in both the model and the SDK class.
- **Patterns to follow:** the status constants and predicates already in `app/models/mollie_pay/sales_invoice.rb`; the `fake_mollie_si` helper in `test/models/mollie_pay/sales_invoice_test.rb`.
- **Test scenarios:**
  - For each of the ten statuses in R1, `SalesInvoice.record_from_mollie` stores a new invoice with that status without raising.
  - A sales invoice with status `canceled` (one l) is invalid, as is `nonsense`.
  - `canceled?` is true for a `cancelled` invoice and false for a `draft` one, on both `MolliePay::SalesInvoice` and `Mollie::SalesInvoice`.
  - `mollie_create_sales_invoice` returns a persisted invoice when Mollie's create response has status `issuing`.
- **Verification:** the sales invoice model, SDK class and billable tests pass, including the new scenarios, and the existing sales invoice tests pass unchanged apart from the one asserting the old spelling.

### U3. Document the statuses and record the change

- **Goal:** The docs match the models and the changelog tells hosts what changed.
- **Requirements:** R7.
- **Dependencies:** U1, U2.
- **Files:** `docs/api.md`, `CHANGELOG.md`.
- **Approach:** Add `canceled` to the Refund row of the statuses table in `docs/api.md` and add a Sales invoice row. Under `[Unreleased]` in `CHANGELOG.md`, add a Fixed entry for both status gaps and a Changed entry marked breaking for the `STATUS_CANCELED` value.
- **Test scenarios:** Test expectation: none -- documentation only.
- **Verification:** the statuses table in `docs/api.md` lists the same values as `Refund::STATUSES` and `SalesInvoice::STATUSES`.

---

## Verification Contract

| Check | Command | Applies to |
|---|---|---|
| Full test suite | `mise exec ruby@4.0.10 -- bundle exec rails test` | U1, U2 |
| Lint | `mise exec ruby@4.0.10 -- bundle exec rubocop` | U1, U2 |

`bin/rails` and `bin/rubocop` pick up system Ruby on this machine and fail to load Bundler, so use the `mise exec` form. CI runs the same suite and lint on Ruby 4.0.

## Definition of Done

- R1, R2, R4, R5 and R7 hold, each proved by the test scenarios of its unit or, for R7, by reading the docs against the constants.
- The full suite passes with zero failures and Rubocop reports no offenses.
- No migration, schema change or new dependency is in the diff.
- No code from an abandoned approach is left in the diff.
