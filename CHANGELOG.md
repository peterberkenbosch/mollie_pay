# Changelog

All notable changes to this project will be documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/).

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
