# API Reference

## Data model

| Table | Key columns | Purpose |
|---|---|---|
| `mollie_pay_customers` | `mollie_id`, `owner` (polymorphic) | Links your model to a Mollie customer |
| `mollie_pay_mandates` | `mollie_id`, `status`, `method` | Stored payment methods (SEPA, card, etc.) |
| `mollie_pay_subscriptions` | `mollie_id`, `status`, `amount`, `interval` | Recurring billing agreements |
| `mollie_pay_payments` | `mollie_id`, `status`, `amount`, `sequence_type` | Individual payment records |
| `mollie_pay_refunds` | `mollie_id`, `status`, `amount` | Refunds against payments |
| `mollie_pay_chargebacks` | `mollie_id`, `amount`, `reason` | Chargebacks against payments |

Only fields needed for business logic and state queries are stored locally.
Display data lives in Mollie and is fetched via `mollie_record`.

### Relationships

```
Owner (your model)
  └── Customer (1:1, polymorphic)
        ├── Payments (1:N)
        │     ├── Refunds (1:N)
        │     └── Chargebacks (1:N)
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

## Payment methods

List available payment methods from the Mollie API. These are fetched live —
no local model or migration is involved.

```ruby
MolliePay.payment_methods                                   # all enabled methods
MolliePay.payment_methods(amount: 1000)                     # filtered by amount (cents)
MolliePay.payment_methods(amount: 1000, currency: "USD")    # with currency override
MolliePay.payment_methods(locale: "nl_NL")                  # localized descriptions
MolliePay.payment_methods(include: "pricing")               # include pricing details

MolliePay.payment_method("ideal")                           # single method details
MolliePay.payment_method("creditcard", locale: "nl_NL")     # with locale
```

A convenience method is available on Billable:

```ruby
organization.mollie_payment_methods(amount: 2500, locale: "nl_NL")
```

Both return Mollie SDK objects (`Mollie::Method`) with `id`, `description`,
`minimum_amount`, `maximum_amount`, `image`, and `status`.

### Caching

Payment methods rarely change. Cache them in your host app to avoid hitting
the Mollie API on every checkout page load:

```ruby
# app/models/organization.rb
def available_payment_methods(amount: nil)
  cache_key = ["mollie_payment_methods", amount, MolliePay.configuration.currency]
  Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    mollie_payment_methods(amount: amount).map do |method|
      {
        id:          method.id,
        description: method.description,
        image:       method.image["svg"],
        status:      method.status
      }
    end
  end
end
```

> **Important:** Cache the serialized data (hashes/arrays), not the
> `Mollie::Method` objects themselves. SDK objects hold network references
> and are not safe for cache serialization.

**Cache invalidation tips:**

- Use `expires_in: 1.hour` — methods change infrequently, but Mollie can
  enable/disable methods at any time
- Include `amount` in the cache key if you filter by amount, since different
  amounts may yield different available methods
- Bust the cache manually when you change payment method settings in the
  Mollie dashboard: `Rails.cache.delete_matched("mollie_payment_methods*")`

## Subscription plan swap (upgrade/downgrade)

Change a customer's subscription amount and/or interval without canceling:

```ruby
organization.mollie_swap_subscription(amount: 4999)                           # change amount only
organization.mollie_swap_subscription(interval: "1 year")                     # change interval only
organization.mollie_swap_subscription(amount: 4999, interval: "1 year")       # change both
organization.mollie_swap_subscription(name: "addon", amount: 1999)            # named subscription
```

This uses the Mollie Update Subscription API (`PATCH`) to modify the existing
subscription in place. The change takes effect on the **next billing cycle** —
Mollie does not calculate proration.

- Returns the existing subscription unchanged if the values are already the same (no API call)
- Raises `SubscriptionNotFound` if no active or pending subscription exists for the name
- Fires `on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:)`

### Proration

Mollie does not handle proration. If you need to charge the upgrade difference
immediately, use the swap hook:

```ruby
def on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:)
  if subscription.amount > previous_amount
    difference = subscription.amount - previous_amount
    mollie_pay_once(
      amount: difference,
      description: "Plan upgrade proration",
      redirect_url: billing_url
    )
  end
end
```

## Errors

| Error | Raised when |
|---|---|
| `MolliePay::ConfigurationError` | `api_key` or `host` is missing at boot, or no `redirect_url` is available |
| `MolliePay::MandateRequired` | `mollie_subscribe` is called without a valid mandate |
| `MolliePay::SubscriptionNotFound` | `mollie_cancel_subscription` is called without an active subscription |
| `MolliePay::PaymentNotCancelable` | `mollie_cancel_payment` is called on a payment Mollie says is not cancelable |

All inherit from `MolliePay::Error < StandardError`.

## Configuration

| Option | Required | Default | Description |
|---|---|---|---|
| `api_key` | Yes | — | Your Mollie API key (`test_*` or `live_*`) |
| `host` | Yes | — | Your application's public URL (e.g. `https://yourapp.com`) |
| `default_redirect_path` | No | — | Path where Mollie sends customers back after payment (e.g. `/payments/:id`) |
| `currency` | No | `"EUR"` | ISO 4217 currency code for new payments/subscriptions |
