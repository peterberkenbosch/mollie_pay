---
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
execution: code
product_contract_source: ce-plan-bootstrap
title: "feat: Adopt the engine-family charter (UUIDv7 greenfield PKs)"
date: 2026-07-14
origin: https://github.com/peterberkenbosch/mollie_pay/issues/111
---

# feat: Adopt the engine-family charter (UUIDv7 greenfield PKs)

## Summary

Bring `mollie_pay` in line with the shared engine-family charter
(`pbcbv/engine-family` `ENGINE-FAMILY.md`) and ADR 003. The one behavioral change is the
primary-key strategy: every engine table moves from integer PKs to UUIDv7 **string** PKs
via a copied `MolliePay::HasUuid` concern, with all foreign-key and polymorphic `*_id`
columns becoming `:string`. This is a greenfield reset (no data backfill), matching how the
BigDecimal money change (v0.6.0) was shipped. The `Billable` concern already matches the
charter's unified polymorphic identity shape and only needs confirmation plus a binding
test. The Mollie webhook controller and its jobs stay, as the one allowed mountable
exception to the headless rule. `AGENTS.md` gains a link to the charter and its PK/webhook
conventions.

---

## Problem Frame

`mollie_pay` predates the engine-family charter. It uses integer primary keys, while the
charter (and its siblings `reservr`, `hunion`) standardize on UUIDv7 string PKs so that ids
are time-ordered, merge/replica-safe, and consistent across the family. ADR 003 records the
decision and prescribes a **greenfield reset** for `mollie_pay` specifically (no
integer to uuid backfill). Issue 111 tracks the four adoption tasks. This plan covers all
four, with the PK conversion as the substantive work and the other three as
confirmation/documentation.

---

## Requirements

Traceable to issue 111:

- **R1 — UUIDv7 greenfield PKs.** Add `MolliePay::HasUuid` (`SecureRandom.uuid_v7`,
  `before_create`). Every engine table gets `id: :string`. All FK columns
  (`customer_id`, `subscription_id`, `payment_id`) and the polymorphic `owner_id` become
  `:string`. Greenfield reset, no backfill.
- **R2 — Confirm `Billable` concern shape.** Verify `MolliePay::Billable` matches the
  charter's unified polymorphic owner-style identity concern, with the host model (`User`
  in the family; `Organization` in the dummy) as the binding point.
- **R3 — Keep the webhook.** The Mollie webhook controller and jobs remain mounted; they
  are the one allowed mountable exception to the headless rule. No removal.
- **R4 — Link the charter.** `AGENTS.md` references the charter and states the UUIDv7 PK
  rule and the webhook exception.

Success criteria: `bin/rails test` and `bin/rubocop` are green; `test/dummy/db/schema.rb`
shows string PKs and string FK/polymorphic columns on every engine table; a host model
including `Billable` round-trips a Mollie customer with string ids.

---

## Key Technical Decisions

- **Greenfield, edit-in-place migrations (not additive `change_column`).** Per ADR 003 the
  reset is greenfield and there is no production data. Edit the existing `create_*`
  migrations to `id: :string` and `type: :string` columns, then regenerate the schema with
  `db:migrate:reset`. This mirrors exactly how the v0.6.0 money change converted the amount
  columns and keeps the migration history clean. Rationale: additive `change_column`
  migrations would need a data migration (integer to uuid) the charter explicitly forbids.
- **`HasUuid` included once via `ApplicationRecord`.** All seven models inherit from
  `MolliePay::ApplicationRecord`; including `HasUuid` there applies the `before_create`
  hook everywhere without per-model edits. Concern body is copied verbatim from the charter
  (family convention: copied idiom, no shared gem).
- **`id ||= SecureRandom.uuid_v7`.** The hook only sets the id when absent, so fixtures and
  callers may supply explicit string ids (required for fixtures under the charter).
- **Dummy host uses a string PK too.** The dummy `Organization` (host binding point) moves
  to a UUIDv7 string PK so the polymorphic `:string` `owner_id` is exercised with real
  string host ids, not integer-cast-to-string. This makes the dummy a faithful stand-in for
  a charter-compliant host `User`.
- **Fixtures carry explicit UUIDv7 string ids.** Per charter §8, string-PK fixtures use
  explicit ids; the polymorphic `owner` on `customers` is set with explicit
  `owner_type` + `owner_id` (not a label reference, which resolves through
  `FixtureSet.identify` with the wrong type). `belongs_to` label references
  (`customer: acme`, `payment: acme_oneoff`) stay — the charter allows label refs that
  resolve via the target's string PK.

---

## Conversion Reference

Every engine table takes `id: :string`; the columns below change type to `:string`.

| Table | FK / polymorphic columns to make `:string` |
|---|---|
| `mollie_pay_customers` | `owner_id` (polymorphic, keep `owner_type`) |
| `mollie_pay_mandates` | `customer_id` |
| `mollie_pay_subscriptions` | `customer_id` |
| `mollie_pay_payments` | `customer_id`, `subscription_id` (nullable) |
| `mollie_pay_refunds` | `payment_id` |
| `mollie_pay_chargebacks` | `payment_id` |
| `mollie_pay_sales_invoices` | `customer_id` |

`add_foreign_key` declarations are unaffected (they work with string columns). Unique and
lookup indexes are unchanged. The dropped `mollie_pay_webhook_events` table is not
reintroduced.

---

## Scope Boundaries

### In scope
- UUIDv7 string PKs and string FK/polymorphic columns across all engine tables (R1).
- Copied `MolliePay::HasUuid` concern (R1).
- Dummy host (`Organization`) string PK to exercise the polymorphic owner (R1).
- Fixture rewrite to explicit string ids and explicit polymorphic owner (R1).
- `Billable` shape confirmation plus a host-binding test (R2).
- `AGENTS.md` charter link and convention notes (R4).

### Non-goals
- **Do not remove or alter the webhook controller/jobs** (R3) — they are the allowed
  mountable exception. No behavioral change to webhook processing.
- No data migration or backfill (greenfield; ADR 003).
- No change to money representation (already BigDecimal as of v0.6.0).
- No change to Mollie API behavior, model business logic, or the public `Billable` method
  surface.

### Deferred to Follow-Up Work
- A separate release/version bump and CHANGELOG entry for this change is a normal release
  task handled after merge, not part of this plan's units.

---

## Implementation Units

### U1. Add `MolliePay::HasUuid` and apply it engine-wide

**Goal:** Provide UUIDv7 string primary keys on every engine model.

**Requirements:** R1.

**Dependencies:** none.

**Files:**
- `app/models/mollie_pay/has_uuid.rb` (new)
- `app/models/mollie_pay/application_record.rb` (include the concern)
- `test/models/mollie_pay/has_uuid_test.rb` (new)

**Approach:** Copy the charter's `HasUuid` idiom verbatim into the `MolliePay` namespace: an
`ActiveSupport::Concern` whose `included` block registers `before_create :set_uuid`, with a
private `set_uuid` that does `self.id ||= SecureRandom.uuid_v7`. Include it in
`MolliePay::ApplicationRecord` so all seven models (`Customer`, `Mandate`, `Subscription`,
`Payment`, `Refund`, `Chargeback`, `SalesInvoice`) inherit it. No per-model edits.

**Patterns to follow:** `ENGINE-FAMILY.md` §2 `HasUuid` example; the sibling engines
`reservr`/`hunion` `HasUuid` concerns.

**Test scenarios:**
- Creating a `Customer` (and one other model, e.g. `Payment`) with no id assigns a
  36-char UUIDv7 string id.
- A record created with an explicit string id keeps that id (the `||=` path).
- The assigned id sorts time-ordered for two records created in sequence (UUIDv7 property).

**Verification:** New models persist with string ids; `has_uuid_test.rb` passes.

---

### U2. Convert engine migrations to string PKs and string FK/polymorphic columns

**Goal:** Every engine table has a `:string` PK and `:string` FK/polymorphic columns.

**Requirements:** R1.

**Dependencies:** U1.

**Files:**
- `db/migrate/20260315142959_create_mollie_pay_customers.rb` (`id: :string`; `t.references :owner, polymorphic: true, type: :string`)
- `db/migrate/20260315143008_create_mollie_pay_mandates.rb` (`id: :string`; `t.references :customer, type: :string`)
- `db/migrate/20260315143014_create_mollie_pay_subscriptions.rb`
- `db/migrate/20260315143020_create_mollie_pay_payments.rb` (`customer_id` and `subscription_id` both `:string`)
- `db/migrate/20260315143026_create_mollie_pay_refunds.rb`
- `db/migrate/20260321000001_create_mollie_pay_chargebacks.rb`
- `db/migrate/20260326000002_create_mollie_pay_sales_invoices.rb`
- `test/dummy/db/schema.rb` (regenerated, not hand-edited)

**Approach:** Greenfield edit-in-place. Add `id: :string` to each `create_table`. Add
`type: :string` to each `t.references` (FK and polymorphic). Leave `add_foreign_key`,
indexes, and non-key columns untouched. The add-column migrations
(`add_amount_tracking_*`, `add_authorized_at_*`, `add_name_*`, `add_checkout_url_*`,
`add_status_indexes_*`, `make_mollie_id_nullable_*`) need no change — they touch no keys.
Do not reintroduce the dropped `mollie_pay_webhook_events` table. Regenerate the dummy
schema with `bin/rails db:migrate:reset` (same procedure the money change used).

**Patterns to follow:** the v0.6.0 money greenfield migration edits; `ENGINE-FAMILY.md` §2
(`id: :string`, `t.references ..., type: :string`).

**Test scenarios:** `Test expectation: none — schema-only unit; behavior is proven by U1 and
the full suite in U4.` Verify by inspecting regenerated `schema.rb`:
- Each `mollie_pay_*` table declares a string `id`.
- `owner_id`, `customer_id`, `subscription_id`, `payment_id` are string columns.
- Foreign keys and unique indexes are preserved.

**Verification:** `db:migrate:reset` succeeds; `schema.rb` shows string PKs and FK columns
on all seven tables; no `webhook_events` table.

---

### U3. Move the dummy host to a UUIDv7 string PK

**Goal:** Exercise the polymorphic `:string` `owner` with a real string-PK host.

**Requirements:** R1.

**Dependencies:** U1.

**Files:**
- `test/dummy/db/migrate/*_create_organizations.rb` (or the dummy's organizations migration; `id: :string`)
- `test/dummy/app/models/organization.rb` (assign a UUIDv7 string id on create)
- `test/dummy/db/schema.rb` (regenerated)

**Approach:** Give the dummy `organizations` table a `:string` PK. In `Organization`, set a
UUIDv7 id on create (a small `before_create` mirroring `HasUuid`, or reuse the same idiom)
so the host id is a string — the value stored in `mollie_pay_customers.owner_id`. Locate how
the dummy creates `organizations` (a `test/dummy/db/migrate` migration or a schema-only
definition) and apply the string-PK change there, then regenerate the dummy schema. This
keeps the polymorphic association charter-faithful (string host ids), rather than relying on
integer-to-string casting.

**Patterns to follow:** charter §4 host binding (`User` includes the concern);
`ENGINE-FAMILY.md` §2 host FK/`*_id` columns are `:string`.

**Test scenarios:**
- A new `Organization` gets a string id.
- An `Organization` including `Billable` creates a `mollie_customer` whose `owner_id`
  equals the organization's string id and `owner_type` is `"Organization"`.

**Verification:** Dummy schema shows a string `organizations.id`; the polymorphic owner
round-trips with string ids.

---

### U4. Rewrite fixtures with explicit UUIDv7 string ids and explicit polymorphic owner

**Goal:** Fixtures load correctly against string PKs and the full suite passes.

**Requirements:** R1.

**Dependencies:** U2, U3.

**Files:**
- `test/fixtures/organizations.yml`
- `test/fixtures/mollie_pay/customers.yml`
- `test/fixtures/mollie_pay/mandates.yml`
- `test/fixtures/mollie_pay/subscriptions.yml`
- `test/fixtures/mollie_pay/payments.yml`
- `test/fixtures/mollie_pay/refunds.yml`
- `test/fixtures/mollie_pay/chargebacks.yml`
- `test/fixtures/mollie_pay/sales_invoices.yml`

**Approach:** Give every fixture record an explicit `id:` UUIDv7 string (hard-coded, stable
values). In `customers.yml`, replace `owner: acme (Organization)` with explicit
`owner_type: Organization` and `owner_id: <organizations.acme id>`. Keep `belongs_to` label
references (`customer: acme`, `payment: acme_oneoff`, `subscription: acme_monthly`) — the
charter permits label refs that resolve via the target's string PK. Cross-check that the
explicit polymorphic `owner_id` matches the `organizations.acme` fixture id exactly.

**Patterns to follow:** `ENGINE-FAMILY.md` §8 (explicit UUIDv7 string ids; explicit
polymorphic ids; label refs allowed for string-PK belongs_to); `reservr`/`hunion` fixtures.

**Test scenarios:**
- The full suite (`bin/rails test`) loads all fixtures and passes with 0 failures/errors.
- A test resolving a `customer` label reference (e.g. a mandate's customer) returns the
  correct `Customer` by string id.
- The `customers(:acme).owner` resolves to `organizations(:acme)` with matching string id.

**Verification:** `bin/rails test` is green; no fixture-load or foreign-key errors.

---

### U5. Confirm `Billable` matches the unified concern shape

**Goal:** Verify (and lock with a test) that the charter identity concern is satisfied.

**Requirements:** R2.

**Dependencies:** U3, U4.

**Files:**
- `app/models/mollie_pay/billable.rb` (verify; change only if a mismatch is found)
- `test/models/mollie_pay/billable_test.rb` (add a host-binding assertion if not already covered)

**Approach:** `Billable` already declares `has_one :mollie_customer, as: :owner` plus the
`has_many :through` associations — this is the charter's polymorphic owner-style identity
concern, with the host model as the binding point. Confirm no change is needed beyond string
PKs. Add or confirm a test that a host model including `Billable` (the dummy `Organization`,
standing in for the family `User`) creates and reads its `mollie_customer` and associated
records through the concern with string ids. Record a one-line note in the PR/plan that the
concern matches the charter unchanged.

**Test scenarios:**
- A host `Organization` including `Billable` responds to `mollie_customer`,
  `mollie_subscriptions`, `mollie_payments`, `mollie_mandates`, `mollie_sales_invoices`.
- `mollie_customer!` creates a `Customer` bound to the host via string `owner_id`.
- Destroying the host cascades to `mollie_customer` (existing `dependent: :destroy`).

**Verification:** `billable_test.rb` passes; concern confirmed charter-compliant.

---

### U6. Link `AGENTS.md` to the charter and codify its conventions

**Goal:** Document charter adoption for future contributors.

**Requirements:** R3, R4.

**Dependencies:** none (can land any time, but write it to reflect the shipped state).

**Files:**
- `AGENTS.md`

**Approach:** Add a short "Engine family charter" reference pointing to
`https://github.com/pbcbv/engine-family/blob/main/ENGINE-FAMILY.md` and ADR 003. State the
two conventions this repo now follows from the charter: (a) UUIDv7 string PKs via
`MolliePay::HasUuid` with `:string` FK/polymorphic columns, and (b) the Mollie webhook
controller + jobs are the one allowed mountable exception to the headless rule. Reconcile
any existing AGENTS.md wording that implies integer PKs.

**Test scenarios:** `Test expectation: none — documentation-only unit.`

**Verification:** `AGENTS.md` links the charter and states the PK and webhook conventions;
no stale integer-PK guidance remains.

---

## Verification Contract

- `bin/rails test` — 0 failures, 0 errors (full suite, all fixtures loaded).
- `bin/rubocop` — 0 offenses.
- `test/dummy/db/schema.rb` — every `mollie_pay_*` table has a string `id`; `owner_id`,
  `customer_id`, `subscription_id`, `payment_id` are string; foreign keys and unique
  indexes intact; no `mollie_pay_webhook_events` table.
- Webhook controller, routes, and jobs unchanged and still covered by their existing tests.

## Definition of Done

- U1–U6 complete and verified.
- Full suite and rubocop green.
- Charter link present in `AGENTS.md`; webhook untouched.
- No data backfill introduced; the change is greenfield.

---

## Risks & Dependencies

- **Fixture id/polymorphic mismatch.** The most likely failure mode is a mismatch between
  the explicit `owner_id` in `customers.yml` and the `organizations.acme` fixture id, or
  `FixtureSet.identify` resolving a label to the wrong type. Mitigation: explicit string ids
  everywhere and explicit polymorphic `owner_type`/`owner_id`; lean on the full-suite run in
  U4 to catch it immediately.
- **Dummy organizations definition location.** The dummy host table may be created by a
  `test/dummy/db/migrate` migration or defined only in the schema; U3 must locate and edit
  the right place before regenerating the schema.
- **Greenfield expectation.** Any downstream consumer that already ran the integer-PK
  migrations must recreate its database. This is the accepted ADR 003 posture and mirrors
  the v0.6.0 money change; note it in the eventual release CHANGELOG (deferred follow-up).

---

## Sources & Research

- Issue 111 "Adopt the engine-family charter" (origin).
- `pbcbv/engine-family` `ENGINE-FAMILY.md` §2 (UUIDv7 `HasUuid`), §3 (headless / webhook
  exception), §4 (polymorphic host identity), §8 (fixtures) and ADR 003 (greenfield reset).
- Local precedent: the v0.6.0 BigDecimal greenfield migration edits and dummy schema
  regeneration procedure.
- Current schema: `test/dummy/db/schema.rb`; migrations under `db/migrate/`;
  `app/models/mollie_pay/{application_record,customer,billable}.rb`; fixtures under
  `test/fixtures/`.
