# API Reference

## Data model

| Table | Key columns | Purpose |
|---|---|---|
| `mollie_pay_customers` | `mollie_id`, `owner` (polymorphic) | Links your model to a Mollie customer |
| `mollie_pay_mandates` | `mollie_id`, `status`, `method` | Stored payment methods (SEPA, card, etc.) |
| `mollie_pay_subscriptions` | `mollie_id`, `status`, `amount`, `interval` | Recurring billing agreements |
| `mollie_pay_payments` | `mollie_id`, `status`, `amount`, `sequence_type` | Individual payment records |
| `mollie_pay_refunds` | `mollie_id`, `status`, `amount` | Refunds against payments |

Only fields needed for business logic and state queries are stored locally.
Display data lives in Mollie and is fetched via `mollie_record`.

### Relationships

```
Owner (your model)
  └── Customer (1:1, polymorphic)
        ├── Payments (1:N)
        │     └── Refunds (1:N)
        ├── Subscriptions (1:N)
        │     └── Payments (1:N, optional)
        └── Mandates (1:N)
```

### Statuses

| Model | Valid statuses |
|---|---|
| Payment | `open`, `pending`, `authorized`, `paid`, `failed`, `canceled`, `expired` |
| Subscription | `pending`, `active`, `suspended`, `canceled`, `completed` |
| Mandate | `pending`, `valid`, `invalid` |
| Refund | `queued`, `pending`, `processing`, `refunded`, `failed` |

### Scopes

```ruby
MolliePay::Payment.paid             # status: paid
MolliePay::Payment.failed           # status: failed
MolliePay::Payment.open             # status: open
MolliePay::Payment.recurring        # sequence_type: recurring
MolliePay::Payment.first_payments   # sequence_type: first

MolliePay::Subscription.active
MolliePay::Subscription.canceled
MolliePay::Subscription.suspended

MolliePay::Mandate.valid_status
MolliePay::Refund.refunded
```

## Through associations

`mollie_payments`, `mollie_subscriptions`, and `mollie_mandates` are real
`has_many :through` associations — they support full ActiveRecord chaining:

```ruby
org.mollie_subscriptions                 # all subscriptions
org.mollie_subscriptions.active          # active only
org.mollie_payments                      # all payments
org.mollie_payments.paid                 # paid only
org.mollie_payments.recurring            # recurring payments
org.mollie_mandates                      # all mandates
org.mollie_mandates.valid_status         # valid only

# Eager loading for admin views (avoids N+1)
User.includes(mollie_customer: :subscriptions).find_each do |user|
  user.mollie_subscriptions.active       # no extra query
end
```

## Fetching live Mollie data

Every local record exposes `mollie_record`, which fetches the full object from
the Mollie API on demand:

```ruby
subscription.mollie_record.next_payment_date
mandate.mollie_record.details
customer.mollie_record.locale
```

This is a live API call — don't use it in loops or list views.

## Amounts

All amounts in MolliePay are **integers representing cents**.

```ruby
payment.amount          # => 2500 (cents)
payment.amount_decimal  # => 25.0 (for display)
payment.mollie_amount   # => { currency: "EUR", value: "25.00" } (Mollie format)
```

The same methods are available on `Subscription` and `Refund`.

## Errors

| Error | Raised when |
|---|---|
| `MolliePay::ConfigurationError` | `api_key` or `host` is missing at boot, or no `redirect_url` is available |
| `MolliePay::MandateRequired` | `mollie_subscribe` is called without a valid mandate |
| `MolliePay::SubscriptionNotFound` | `mollie_cancel_subscription` is called without an active subscription |

All inherit from `MolliePay::Error < StandardError`.

## Configuration

| Option | Required | Default | Description |
|---|---|---|---|
| `api_key` | Yes | — | Your Mollie API key (`test_*` or `live_*`) |
| `host` | Yes | — | Your application's public URL (e.g. `https://yourapp.com`) |
| `default_redirect_path` | No | — | Path where Mollie sends customers back after payment (e.g. `/payments/:id`) |
| `currency` | No | `"EUR"` | ISO 4217 currency code for new payments/subscriptions |
