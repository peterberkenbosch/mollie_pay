---
title: "Top-level mollie-api-ruby classes build endpoints Mollie does not have"
date: 2026-11-25
category: integration-issues
module: MolliePay Subscription, Refund, Billable, ProcessWebhookJob, TestHelper
problem_type: integration_issue
component: payments
symptoms:
  - "Mollie::ResourceNotFoundError: 404 Not Found: Invalid resource endpoint from Subscription#mollie_record"
  - "sub_ and re_ webhooks discarded without a failure in the job log"
  - "mollie_refund fails against the live API while the test suite stays green"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags:
  - mollie-api
  - sdk-compatibility
  - nested-resources
  - webmock
  - refunds
  - subscriptions
---

# Top-level mollie-api-ruby classes build endpoints Mollie does not have

## Problem

The engine fetched subscriptions and refunds, and created refunds, through the SDK's top-level classes `Mollie::Subscription` and `Mollie::Refund`. Mollie has no endpoint for those calls, so every one of them failed against the real API while the whole suite passed. Issue #135 reported the subscription case; the refund cases turned up while fixing it.

## Symptoms

- `Mollie::Subscription.get(sub_id, customer_id: cst_id)` raised `Mollie::ResourceNotFoundError: 404 Not Found: Invalid resource endpoint`. The same call through `Mollie::Customer::Subscription` returned the subscription (reported against Mollie test mode with mollie-api-ruby 4.19.1).
- `ProcessWebhookJob` has `discard_on Mollie::ResourceNotFoundError`, so a `sub_` webhook that hit the wrong endpoint was dropped with nothing logged as a failure. A `re_` webhook went through the same wrong-path mechanism.
- `Billable#mollie_refund` posted to `POST /v2/refunds`, which Mollie does not document. Only `POST /v2/payments/{paymentId}/refunds` exists.

## What Didn't Work

- Method-level stubs (`Mollie::Subscription.stub(:get, response)`) replace the class method before any URL is built, so they can never see a wrong path.
- The public helper `webmock_mollie_refund_create` stubbed `POST /v2/refunds`. It pinned the wrong endpoint as if it were right, so the refund tests that ran the full SDK pipeline passed against it.

## Solution

Call the nested SDK classes, which build the parent into the path:

```ruby
# before: GET /v2/subscriptions/sub_x?customerId=cst_x
Mollie::Subscription.get(mollie_id, customer_id: customer.mollie_id)
# after:  GET /v2/customers/cst_x/subscriptions/sub_x
Mollie::Customer::Subscription.get(mollie_id, customer_id: customer.mollie_id)

# before: POST /v2/refunds with paymentId in the body
Mollie::Refund.create(paymentId: payment.mollie_id, amount: ..., idempotency_key: ...)
# after:  POST /v2/payments/tr_x/refunds
Mollie::Payment::Refund.create(payment_id: payment.mollie_id, amount: ..., idempotency_key: ...)
```

The parent option must be the snake_case `payment_id:` / `customer_id:` key: `Mollie::Base.request` removes `options[parent_id]` or `data[parent_id]` and puts it in the path. A camelCase `paymentId:` stays in the body.

## Why This Works

`Mollie::Base.resource_name` (mollie-api-ruby `lib/mollie/base.rb`) pluralizes the class path and joins it around the parent id only when the class is two levels deep and a parent id is given. A top-level class yields just `subscriptions` or `refunds`. Its `parent_id` key is `:mollie_id`, so a `customer_id:` or `payment_id:` option is not consumed as the parent and is sent as a query or body parameter instead. The SDK raises no error for this; Mollie answers 404.

## Prevention

- `test/lib/mollie_pay/sdk_resource_paths_test.rb` fails when engine code calls `get`, `create`, `update`, `delete` or `cancel` on top-level `Mollie::Subscription`, `Mollie::Refund` or `Mollie::Chargeback`.
- Pin every new SDK call with WebMock on the exact URL from Mollie's API reference, not with a method stub. A method stub proves only that the method was called.
- When a webhook job discards on `ResourceNotFoundError`, a wrong endpoint looks the same as a deleted resource. Test the job against the real path at least once.
- Top-level `Mollie::Refund.all` and `Mollie::Subscription.all` are valid (`GET /v2/refunds`, `GET /v2/subscriptions` list across the organization). The check targets only single-resource calls.

## Related Issues

- GitHub issue #135
- `docs/solutions/integration-issues/mollie-chargeback-model-api-discovery.md`: another case where the SDK's classes did not match the live API.
