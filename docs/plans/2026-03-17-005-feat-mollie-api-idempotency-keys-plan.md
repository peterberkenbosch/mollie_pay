---
title: "feat: Add Mollie API idempotency keys to all POST requests"
type: feat
status: active
date: 2026-03-17
---

# feat: Add Mollie API idempotency keys to all POST requests

## Overview

Mollie supports idempotency keys via the `Idempotency-Key` HTTP header on POST
requests. If a request fails due to network issues and is retried with the same
key within 1 hour, Mollie returns the cached response instead of creating a
duplicate resource. The mollie-api-ruby gem supports this natively via the
`idempotency_key:` parameter on `.create()` calls.

Source: https://docs.mollie.com/reference/api-idempotency

## Proposed Solution

Add `idempotency_key: SecureRandom.uuid` to all four Mollie API POST calls in
`Billable`:

1. `Mollie::Payment.create` (line 148)
2. `Mollie::Customer.create` (line 170)
3. `Mollie::Customer::Subscription.create` (line 59)
4. `Mollie::Refund.create` (line 87)

UUID4 is the recommended key format per Mollie docs. A random key per call is
correct — idempotency protects against network-level retries, not business-level
duplicates (which are handled by our existing idempotency guards).

## Acceptance Criteria

- [ ] All four Mollie POST calls include `idempotency_key: SecureRandom.uuid`
- [ ] Tests verify idempotency keys are passed through
- [ ] Documentation updated
