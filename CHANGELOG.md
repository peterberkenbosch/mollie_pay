# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.6.0] - 2026-07-13

### Changed
- **Breaking:** All monetary amounts are now exact `BigDecimal` instead of integer
  cents, across the public interface and storage. Pass amounts as `BigDecimal`
  (e.g. `BigDecimal("25.00")`) to `mollie_pay_once`, `mollie_pay_first`,
  `mollie_subscribe`, `mollie_swap_subscription`, `mollie_refund`,
  `MolliePay.payment_methods`, and sales-invoice `unit_price`. Every model amount
  attribute now returns `BigDecimal`.
- Money columns are stored as TEXT-affinity `:string` and cast via a registered
  `:money` type (`MolliePay::DecimalMoneyType`); never `:decimal` (SQLite NUMERIC
  affinity stores REAL/float and loses precision). Conversion to Mollie's decimal
  string wire format happens only at the API boundary.
- `ApplicationRecord.mollie_value_to_cents` renamed to `mollie_value_to_decimal`.

### Removed
- **Breaking:** `amount_decimal` on all models. Use `amount`, which is now `BigDecimal`.

### Migration Required
- Money columns changed from `integer` (cents) to `string` (exact BigDecimal as text).
  This is a greenfield schema change with no data migration, consistent with ADR 003's
  greenfield reset for `mollie_pay`. A fresh install needs no extra step. An existing
  database must either be recreated, or have each money column altered to `string` with
  its values converted from cents to decimal (`amount / 100.0`).

## [0.5.0] - 2026-03-27

### Added
- Sales Invoices API (beta): `MolliePay.create_sales_invoice`, `sales_invoice`,
  `sales_invoices`, `update_sales_invoice`, `delete_sales_invoice`; Billable
  `mollie_create_sales_invoice` and `mollie_mark_invoice_paid`; a `SalesInvoice`
  model synced via `record_from_mollie` with `issued`/`paid`/`overdue` scopes and
  `on_mollie_sales_invoice_issued` / `on_mollie_sales_invoice_paid` hooks.
- Next-Gen Webhooks: `/webhook_events` endpoint with HMAC-SHA256 signature
  verification via `webhook_signing_secret` (accepts an array for rotation).
- Mandates: `mollie_create_mandate` and `mollie_revoke_mandate` for direct SEPA
  Direct Debit mandate management.
- Customer operations: `mollie_update_customer` and `mollie_delete_customer`
  (cascades to local records).
- Subscriptions: `mollie_swap_subscription` for plan upgrade/downgrade via Mollie
  PATCH, firing `on_mollie_subscription_swapped`.
- Payments: `mollie_update_payment` and `mollie_cancel_payment`.
- Payment methods: `MolliePay.payment_methods` and `MolliePay.payment_method`
  (read-only listing with optional amount/currency/locale filters).
- Chargebacks: a `Chargeback` model with automatic detection via payment webhooks
  and `on_mollie_chargeback_received` / `on_mollie_chargeback_reversed` hooks.
- Mollie API idempotency keys on all POST requests.

### Changed
- Test fixtures aligned with real Mollie API responses (camelCase JSON).
- Dependency bumps: sqlite3, webmock.

### Documentation
- SEPA mandate consent and compliance guide (`docs/mandates.md`).
- README slimmed with reference content moved into `docs/`.

## [0.4.0] - 2026-03-17

### Changed
- **Breaking:** Removed `WebhookEvent` model and `mollie_pay_webhook_events` table.
  The controller now validates and enqueues `ProcessWebhookJob` directly with the
  `mollie_id` — no intermediate database record. Processing logic moved into the
  job. Domain models own state, ActiveJob owns retries.
- `ProcessWebhookJob` accepts `mollie_id` string instead of `event_id` integer

### Fixed
- Webhook status transitions: Mollie sends multiple webhooks per resource ID
  (e.g., `authorized` then `paid`). The old unique index on `webhook_events`
  silently dropped subsequent webhooks, leaving payments stuck
- `Payment.record_from_mollie` and `Refund.record_from_mollie` now rescue
  `RecordNotUnique` on concurrent INSERT race (matching existing Subscription)
- `ProcessWebhookJob` discards `ActiveRecord::RecordNotFound` instead of retrying
  5 times for locally unknown subscription/refund IDs

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` to drop the
  `mollie_pay_webhook_events` table

## [0.3.0] - 2026-03-17

### Added
- Named subscriptions: `name` column on subscriptions (default: `"default"`)
  enables multiple concurrent subscriptions per customer
- `name:` keyword argument on `mollie_subscribe`, `mollie_cancel_subscription`,
  `mollie_subscribed?`, and `mollie_subscription` (default: `"default"`)
- `Subscription::ACTIVE_STATUSES` constant for pending/active status checks
- `named` scope on Subscription model
- Partial unique index on `[customer_id, name]` WHERE status IN
  ('pending', 'active') — database-level idempotency guarantee
- Race condition handling: orphaned Mollie subscriptions are canceled when
  `RecordNotUnique` is raised during concurrent creates
- Subscription name stored in Mollie metadata for webhook recovery

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` for the
  `name` column and partial unique index on subscriptions

## [0.2.0] - 2026-03-17

### Added
- `has_many :mollie_subscriptions`, `:mollie_payments`, `:mollie_mandates` through
  associations on Billable concern
- `start_date:` optional parameter on `mollie_subscribe` — defer first subscription
  charge when first payment covers the first period
- `method:` parameter on `mollie_pay_first` and `mollie_pay_once` — specify Mollie
  payment method (`"ideal"`, `"creditcard"`, etc.)
- `metadata:` pass-through parameter on `mollie_pay_first` and `mollie_pay_once` —
  arbitrary hash forwarded to the Mollie API
- Idempotency guard on `mollie_subscribe` — returns existing subscription if one is
  pending or active
- Tutorial Parts 6-8 (payment method selection, through associations, production
  hardening)

### Fixed
- `Payment.record_from_mollie` now links recurring payments to parent subscription
  via `subscription_id`
- Webhook event deduplication: database unique index on `mollie_id` +
  `RecordNotUnique` rescue replaces application-level check

### Changed
- State query methods (`mollie_subscribed?`, `mollie_subscription`, `mollie_mandated?`,
  `mollie_mandate`) use `has_many :through` associations instead of manual customer
  delegation
- Removed manual `mollie_payments` method from Billable — replaced by identical
  `has_many :through` association (no host app changes needed)

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` for unique index on
  `mollie_pay_webhook_events.mollie_id`

## [0.1.0] - 2026-03-01

Initial release.
