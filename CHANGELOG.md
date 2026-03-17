# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.4.0] - 2026-03-17

### Fixed
- Webhook events: removed unique index on `mollie_id` — Mollie sends multiple
  webhooks for the same resource ID on status transitions (e.g., `authorized` →
  `paid`). The unique index silently dropped subsequent webhooks, leaving payments
  stuck in intermediate states
- `Payment.record_from_mollie` and `Refund.record_from_mollie` now rescue
  `RecordNotUnique` on concurrent INSERT race (matching existing Subscription pattern)
- `ProcessWebhookJob` now discards `ActiveRecord::RecordNotFound` instead of retrying
  5 times for locally unknown subscription/refund IDs

### Migration Required
- Run `rails mollie_pay:install:migrations && rails db:migrate` to remove the
  unique index on `mollie_pay_webhook_events.mollie_id`

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
