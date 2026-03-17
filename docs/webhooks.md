# Webhooks

## Endpoint

Point your Mollie dashboard webhook URL to:

```
POST https://yourapp.com/mollie_pay/webhooks
```

## How it works

```
POST /mollie_pay/webhooks              (from Mollie)
  → validate mollie_id format           (reject junk IDs with 422)
  → ProcessWebhookJob.perform_later     (enqueue for async processing)
  → head :ok                            (respond immediately)

ProcessWebhookJob:
  → route by ID prefix (tr_ → Payment, sub_ → Subscription, re_ → Refund)
  → fetch full object from Mollie API
  → upsert local record via record_from_mollie
  → fire on_mollie_* hook on billable (only on status transitions)
```

No event model, no mutable state. The controller validates and enqueues. The job
fetches from Mollie and delegates to domain models. MolliePay responds immediately
with `200 OK`, then processes asynchronously via Active Job. On failure, the job
retries with polynomial backoff (up to 5 attempts). Resources not found on Mollie
(404) or locally (unknown subscription/refund IDs) are discarded, not retried.

## Verification

No signature verification is needed. Mollie's webhook pattern sends only an
`id` parameter, which MolliePay validates against the format
`(tr|sub|re)_[a-zA-Z0-9]+` and then fetches directly from the Mollie API.
The API key is the verification — only your key can fetch your objects.

## Idempotency

Hooks fire **only on actual status transitions**. If Mollie sends the same
webhook multiple times (which it does routinely), the local record is updated
but hooks are not re-triggered. As a best practice, implement your `on_mollie_*`
callbacks **idempotently** — they are safe for side effects (send emails,
provision access, update billing state) but should handle the rare case of
being called more than once for the same transition.

Transition timestamps (`paid_at`, `canceled_at`, `failed_at`, `expired_at`,
`refunded_at`, `mandated_at`) are set once when the transition is first
observed and never overwritten.

## Active Job

MolliePay requires Active Job for webhook processing. Configure your queue
adapter in `config/application.rb`:

```ruby
config.active_job.queue_adapter = :solid_queue # or :sidekiq, :good_job, etc.
```

Webhook jobs are enqueued on the `:default` queue. Processing includes:

- **Retry policy:** polynomial backoff, up to 5 attempts on Mollie API and database errors
- **Discard policy:** Mollie 404s and locally unknown subscription/refund IDs are discarded immediately
- **Idempotency:** `record_from_mollie` uses `find_or_initialize_by` — safe to process the same webhook multiple times

## Rate limiting

The webhook endpoint is publicly accessible by design. Consider rate limiting
it at the infrastructure level:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("mollie_webhooks", limit: 100, period: 60) do |req|
  req.path == "/mollie_pay/webhooks" && req.post? && req.ip
end
```
