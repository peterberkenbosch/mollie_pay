---
title: "feat: Next-Gen Webhooks Phase 1 — HMAC verification and event receiving"
type: feat
status: completed
date: 2026-03-22
deepened: 2026-03-22
github_issue: 70
origin: docs/brainstorms/2026-03-22-next-gen-webhooks-research.md
---

# feat: Next-Gen Webhooks Phase 1 — HMAC verification and event receiving

## Enhancement Summary

**Deepened on:** 2026-03-22
**Agents used:** security-sentinel, kieran-rails-reviewer, architecture-strategist, code-simplicity-reviewer, learnings-researcher

### Key Improvements from Deepening

1. **Security:** Added explicit `sha256=` prefix validation, warn-level logging for invalid signatures, boot-time warning when no secret configured
2. **Convention fix:** Replaced mid-method guard clause with expanded conditional (per AGENTS.md)
3. **Simplified job:** Removed commented-out case branches and unnecessary variables — just log the event
4. **Simplified test helper:** Removed YAGNI `entity`/`_embedded` parameter
5. **Added `require "openssl"`** to signature module for explicit dependency
6. **Documented architectural departure:** Full event hash as job argument (vs classic's single ID string) is intentional to avoid extra API fetch

## Overview

Add first-class support for receiving and verifying Mollie's Next-Gen Webhook
events. This is the foundation that Sales Invoices (#69) and future event
types will build on. Phase 1 focuses on **receiving and verifying** — no
OAuth, no subscription management API. Users create webhook subscriptions
via the Mollie Dashboard, and mollie_pay handles the incoming events with
HMAC signature verification.

(see origin: `docs/brainstorms/2026-03-22-next-gen-webhooks-research.md`)

## Problem Statement

Mollie's Next-Gen Webhooks deliver events (like `sales-invoice.paid`) with
HMAC-SHA256 signed payloads. The current mollie_pay architecture only handles
classic webhooks (resource ID in POST body, no signature). Without next-gen
support, mollie_pay cannot receive sales invoice events, payment link events,
or any future event types Mollie adds to this system.

## Proposed Solution

### New endpoint alongside classic webhooks

```
Classic: POST /mollie_pay/webhooks           → WebhooksController#create (unchanged)
Next-gen: POST /mollie_pay/webhook_events    → WebhookEventsController#create (new)
```

Both endpoints coexist. Classic webhooks are not modified.

### Configuration

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"]
  config.webhook_signing_secret = ENV["MOLLIE_WEBHOOK_SIGNING_SECRET"]
  # For secret rotation, pass an array:
  # config.webhook_signing_secret = [ENV["MOLLIE_WEBHOOK_SECRET_NEW"], ENV["MOLLIE_WEBHOOK_SECRET_OLD"]]
end
```

If `webhook_signing_secret` is not configured (`nil`, `""`, or `[]`), all
events are accepted without verification. A boot-time warning is logged to
alert operators that verification is disabled.

### Signature verification

The `X-Mollie-Signature` header contains `sha256=<hex_hmac>`. Verification
uses `request.raw_post` (never re-serialized params) with timing-safe
comparison via `ActiveSupport::SecurityUtils.secure_compare`.

### Event processing

Events are enqueued as `ProcessWebhookEventJob` with the parsed JSON hash
(camelCase string keys, as received from Mollie). This is an intentional
departure from the classic pattern (which passes a single `mollie_id` string)
because next-gen events include embedded entity data, avoiding an extra API
fetch. The job routes by event type. Unknown types are logged and accepted
(200 OK).

## Technical Approach

### Files to create

| File | Purpose |
|------|---------|
| `app/controllers/mollie_pay/webhook_events_controller.rb` | Receive + verify next-gen events |
| `app/jobs/mollie_pay/process_webhook_event_job.rb` | Route events by type |
| `lib/mollie_pay/webhook_signature.rb` | HMAC verification module |
| `test/controllers/mollie_pay/webhook_events_controller_test.rb` | Controller tests |
| `test/jobs/mollie_pay/process_webhook_event_job_test.rb` | Job tests |

### Files to modify

| File | Change |
|------|--------|
| `config/routes.rb` | Add `resources :webhook_events, only: :create` |
| `lib/mollie_pay/configuration.rb` | Add `webhook_signing_secret` + `webhook_signing_secrets` |
| `lib/mollie_pay/errors.rb` | Add `InvalidSignature` |
| `lib/mollie_pay.rb` | Require `webhook_signature` |
| `lib/mollie_pay/test_helper.rb` | Add `post_signed_webhook_event` helper |
| `docs/webhooks.md` | Add next-gen section |
| `AGENTS.md` | Document new endpoint and configuration |

### Implementation details

#### WebhookEventsController

```ruby
# app/controllers/mollie_pay/webhook_events_controller.rb
module MolliePay
  class WebhookEventsController < ApplicationController
    skip_forgery_protection

    def create
      raw_body = request.raw_post
      head :bad_request and return if raw_body.blank?

      verify_signature!(raw_body)

      event = JSON.parse(raw_body)

      if event["id"].present? && event["type"].present?
        ProcessWebhookEventJob.perform_later(event)
        head :ok
      else
        head :unprocessable_entity
      end
    rescue JSON::ParserError
      head :bad_request
    rescue MolliePay::InvalidSignature => e
      Rails.logger.warn("[MolliePay] Webhook signature verification failed: #{e.message}")
      head :bad_request
    end

    private

      def verify_signature!(raw_body)
        secrets = MolliePay.configuration.webhook_signing_secrets
        return if secrets.nil? # No secret configured — skip verification

        MolliePay::WebhookSignature.verify!(
          raw_body,
          request.headers["X-Mollie-Signature"],
          secrets
        )
      end
  end
end
```

**Design notes (from review):**
- Uses expanded conditional for field validation (not mid-method guard clause,
  per AGENTS.md convention)
- Logs `InvalidSignature` at `warn` level before returning 400
- Returns 400 for all rejection cases (invalid signature, malformed body, empty body)
- Returns 422 only for valid JSON missing required `id`/`type` fields

#### WebhookSignature module

```ruby
# lib/mollie_pay/webhook_signature.rb
require "openssl"

module MolliePay
  module WebhookSignature
    module_function

    def verify!(payload, signature_header, secrets)
      raise MolliePay::InvalidSignature, "Missing signature" if signature_header.blank?
      raise MolliePay::InvalidSignature, "Invalid signature format" unless signature_header.start_with?("sha256=")

      provided = signature_header.delete_prefix("sha256=")

      verified = Array(secrets).any? do |secret|
        calculated = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
        ActiveSupport::SecurityUtils.secure_compare(calculated, provided)
      end

      raise MolliePay::InvalidSignature, "Invalid signature" unless verified
    end
  end
end
```

**Security enhancements (from review):**
- Explicit `sha256=` prefix validation before HMAC computation
- `require "openssl"` for explicit dependency declaration
- `module_function` for stateless utility — never included, only called directly

#### Configuration additions

```ruby
# lib/mollie_pay/configuration.rb
attr_accessor :webhook_signing_secret

# Returns nil (not configured) or a non-empty array of secrets.
# Treats nil, "", and [] as "not configured" — prevents silent rejection
# when empty array is passed (Array([]).any? would always return false).
def webhook_signing_secrets
  secrets = Array(webhook_signing_secret).reject(&:blank?)
  secrets.empty? ? nil : secrets
end
```

#### ProcessWebhookEventJob

```ruby
# app/jobs/mollie_pay/process_webhook_event_job.rb
module MolliePay
  class ProcessWebhookEventJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    # Phase 2: add discard_on for errors that should not retry

    def perform(event)
      Rails.logger.info("[MolliePay] Received webhook event: #{event['type']} (#{event['entityId']})")
    end
  end
end
```

**Simplification (from review):** No `case` statement or commented-out branches.
Just log the event. When Phase 2 (#69) adds handlers, add the `case` routing
then. The `retry_on` matches the existing `ProcessWebhookJob` pattern and is
forward-looking for when handlers make API calls.

#### Route

```ruby
# config/routes.rb
MolliePay::Engine.routes.draw do
  resources :webhooks,       only: :create
  resources :webhook_events, only: :create
end
```

#### Test helper

```ruby
# In lib/mollie_pay/test_helper.rb

WEBHOOK_TEST_SECRET = "test_whsec_000000000000000000000000".freeze

def post_signed_webhook_event(event_type:, entity_id:, secret: WEBHOOK_TEST_SECRET)
  payload = {
    resource: "event",
    id: "whe_test#{SecureRandom.hex(8)}",
    type: event_type,
    entityId: entity_id,
    createdAt: Time.current.iso8601
  }.to_json

  headers = { "CONTENT_TYPE" => "application/json" }
  if secret
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
    headers["HTTP_X_MOLLIE_SIGNATURE"] = signature
  end

  post mollie_pay.webhook_events_path, params: payload, headers: headers
end
```

**Simplification (from review):** Removed `entity`/`_embedded` parameter (YAGNI —
no handler consumes embedded data in Phase 1). Add when Phase 2 needs it.

**Test setup note:** Tests using this helper must configure the signing secret:

```ruby
setup do
  MolliePay.configuration.webhook_signing_secret = MolliePay::TestHelper::WEBHOOK_TEST_SECRET
end
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Valid signature | 200 OK, enqueue job |
| Invalid signature | 400 Bad Request, log at warn |
| Missing `sha256=` prefix | 400 Bad Request (invalid format) |
| Missing signature + secret configured | 400 Bad Request |
| Missing signature + no secret | 200 OK, accept |
| Valid signature + no secret configured | 200 OK, accept (skip verification) |
| Empty body | 400 Bad Request |
| Malformed JSON | 400 Bad Request |
| Missing `id` or `type` fields | 422 Unprocessable Entity |
| Unknown event type | 200 OK, log at info level |
| Duplicate event ID | 200 OK, rely on handler idempotency |
| Secret rotation (array) | Try each secret, any match = valid |
| `webhook_signing_secret = []` | Treated as "not configured" |
| `webhook_signing_secret = ""` | Treated as "not configured" |

## Security Considerations

- **`request.raw_post`** for HMAC input — never re-serialize from params
  (confirmed critical by learnings-researcher: chargeback solution documented
  this pattern)
- **`ActiveSupport::SecurityUtils.secure_compare`** — timing-safe, delegates to
  OpenSSL C-level constant-time comparison
- **Explicit `sha256=` prefix validation** before HMAC computation — reject
  malformed headers early
- **Log invalid signature attempts** at `warn` level with error message (no
  payload content to avoid data leakage)
- **Boot-time warning** when no signing secret is configured — operators see
  that verification is disabled
- **No replay prevention via timestamp** — Mollie's signature format doesn't
  include a timestamp (unlike Stripe/Paddle). Accepted risk for Phase 1.
  Phase 2 handlers MUST be idempotent.
- `skip_forgery_protection` on the controller (external POST, no CSRF token)

## Acceptance Criteria

- [ ] `webhook_signing_secret` config option (string or array)
- [ ] `webhook_signing_secrets` method returns nil or non-empty array
- [ ] `MolliePay::WebhookSignature.verify!` with HMAC-SHA256 verification
- [ ] Explicit `sha256=` prefix validation in signature module
- [ ] `MolliePay::InvalidSignature` error class
- [ ] `POST /mollie_pay/webhook_events` route
- [ ] `WebhookEventsController` receives events, verifies signature, enqueues job
- [ ] Returns 200 for valid events, 400 for invalid signature/body, 422 for missing fields
- [ ] Logs invalid signature attempts at warn level
- [ ] Accepts all events when no signing secret configured (with boot-time warning)
- [ ] Secret rotation: accepts if ANY secret in array matches
- [ ] `ProcessWebhookEventJob` logs received events
- [ ] Job has `retry_on` and `queue_as :default` matching existing pattern
- [ ] `post_signed_webhook_event` test helper with configurable secret
- [ ] Controller tests: valid sig, invalid sig, malformed sig format, missing sig+secret, missing sig+no secret, empty body, malformed JSON, missing fields
- [ ] Job tests: event logging
- [ ] `docs/webhooks.md` updated with next-gen section
- [ ] `AGENTS.md` updated with new endpoint, config, and camelCase key contract
- [ ] `require "openssl"` in webhook_signature.rb

## Scope Boundaries (explicit non-goals)

- **No OAuth / webhook subscription management** — users create subscriptions
  via Mollie Dashboard, not via API
- **No event type handlers** — Phase 2 (#69) adds sales invoice handlers,
  Phase 3 adds other types. This PR only adds the infrastructure.
- **No WebhookEvent model** — consistent with AGENTS.md architecture
- **No Mollie SDK extension** — that's a separate upstream PR
- **No modification to classic webhooks** — they remain unchanged
- **No event ID deduplication** — rely on handler idempotency (Phase 2 concern)

## Dependencies & Risks

- **Beta API** — Mollie may change the payload structure, event types, or
  signature format. Keep the implementation flexible.
- **No timestamp in signature** — unlike Stripe, Mollie doesn't include a
  timestamp. Replay attacks are mitigated by handler idempotency.
- **OAuth-only subscription management** — users must manually set up webhook
  subscriptions in the Mollie Dashboard until Mollie Connect is added (#55)

## Sources & References

### Origin

- **Origin document:** [docs/brainstorms/2026-03-22-next-gen-webhooks-research.md](../../brainstorms/2026-03-22-next-gen-webhooks-research.md)
  Key decisions carried forward: HMAC verification pattern from PHP SDK,
  coexistence with classic webhooks, configurable signing secret, no
  WebhookEvent model

### Institutional Learnings Applied

- **Chargeback solution** (`docs/solutions/integration-issues/mollie-chargeback-model-api-discovery.md`):
  Use `request.raw_post` for HMAC input, use camelCase in test fixtures matching
  real API, separate persistence from hook dispatch

### Internal References

- Classic webhook controller: `app/controllers/mollie_pay/webhooks_controller.rb`
- ProcessWebhookJob pattern: `app/jobs/mollie_pay/process_webhook_job.rb`
- Configuration: `lib/mollie_pay/configuration.rb`
- Errors: `lib/mollie_pay/errors.rb`
- Test helpers: `lib/mollie_pay/test_helper.rb`

### External References

- Mollie Next-Gen Webhooks: https://docs.mollie.com/reference/webhooks-new
- Mollie Webhooks Best Practices: https://docs.mollie.com/docs/webhooks-best-practices
- PHP SDK SignatureValidator: https://github.com/mollie/mollie-api-php
- Stripe webhook.rb (pattern): https://github.com/stripe/stripe-ruby/blob/master/lib/stripe/webhook.rb
- Pay gem webhook handling: https://github.com/pay-rails/pay

### Related Work

- Next-Gen Webhooks issue: #70
- Sales Invoices issue: #69
- Mollie Connect issue: #55
