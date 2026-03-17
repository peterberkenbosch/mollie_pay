# Mollie API Full Coverage — Research Findings

> Research conducted 2026-03-17 for MolliePay v0.4.0
> Source: https://docs.mollie.com/reference/overview

---

## Complete Mollie API Surface

### Accepting Payments

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create payment | POST | `/payments` | Core endpoint. Supports oneoff, first, recurring |
| List payments | GET | `/payments` | Paginated |
| Get payment | GET | `/payments/{id}` | Includes amount tracking fields |
| Update payment | PATCH | `/payments/{id}` | Only open/pending payments |
| Cancel payment | DELETE | `/payments/{id}` | Only authorized payments |
| Release authorization | POST | `/payments/{id}/authorizations/release` | Release held funds |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| List methods | GET | `/methods` | Enabled methods for current profile |
| List all methods | GET | `/methods?includeWallets=true` | All available methods |
| Get method | GET | `/methods/{id}` | Single method details |
| Enable method | POST | `/profiles/{id}/methods/{method}` | Connect only |
| Disable method | DELETE | `/profiles/{id}/methods/{method}` | Connect only |
| Enable issuer | POST | `/profiles/{id}/methods/{method}/issuers/{issuerId}` | Connect only |
| Disable issuer | DELETE | `/profiles/{id}/methods/{method}/issuers/{issuerId}` | Connect only |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create refund | POST | `/payments/{paymentId}/refunds` | ✅ Supported |
| List payment refunds | GET | `/payments/{paymentId}/refunds` | Not yet supported |
| Get refund | GET | `/payments/{paymentId}/refunds/{id}` | ✅ Supported |
| Cancel refund | DELETE | `/payments/{paymentId}/refunds/{id}` | Not yet supported |
| List all refunds | GET | `/refunds` | Not yet supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| List payment chargebacks | GET | `/payments/{paymentId}/chargebacks` | Not supported |
| Get chargeback | GET | `/payments/{paymentId}/chargebacks/{id}` | Not supported |
| List all chargebacks | GET | `/chargebacks` | Not supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create capture | POST | `/payments/{paymentId}/captures` | Not supported |
| List captures | GET | `/payments/{paymentId}/captures` | Not supported |
| Get capture | GET | `/payments/{paymentId}/captures/{id}` | Not supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Apple Pay session | POST | `/wallets/applepay/sessions` | Not supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create payment link | POST | `/payment-links` | Not supported |
| List payment links | GET | `/payment-links` | Not supported |
| Get payment link | GET | `/payment-links/{id}` | Not supported |
| Update payment link | PATCH | `/payment-links/{id}` | Not supported |
| Delete payment link | DELETE | `/payment-links/{id}` | Not supported |
| Get link payments | GET | `/payment-links/{id}/payments` | Not supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| List terminals | GET | `/terminals` | POS devices |
| Get terminal | GET | `/terminals/{id}` | POS devices |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create route | POST | `/payments/{paymentId}/routes` | Delayed routing (Connect) |
| List routes | GET | `/payments/{paymentId}/routes` | Delayed routing (Connect) |
| Get route | GET | `/payments/{paymentId}/routes/{id}` | Delayed routing (Connect) |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create session | POST | `/sessions` | Beta feature |
| Get session | GET | `/sessions/{id}` | Beta feature |

### Receiving Orders

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create order | POST | `/orders` | E-commerce orders with lines |
| List orders | GET | `/orders` | Paginated |
| Get order | GET | `/orders/{id}` | Includes lines and embedded payments |
| Update order | PATCH | `/orders/{id}` | Addresses and metadata |
| Cancel order | DELETE | `/orders/{id}` | Cancel entire order |
| Manage lines | PATCH | `/orders/{id}/lines` | Batch line operations |
| Cancel lines | DELETE | `/orders/{id}/lines` | Cancel specific lines |
| Update line | PATCH | `/orders/{id}/lines/{lineId}` | Single line update |
| Create order payment | POST | `/orders/{id}/payments` | Retry payment for order |
| Create order refund | POST | `/orders/{id}/refunds` | Line-based refund |
| List order refunds | GET | `/orders/{id}/refunds` | Order-scoped refunds |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create shipment | POST | `/orders/{orderId}/shipments` | Triggers capture |
| List shipments | GET | `/orders/{orderId}/shipments` | |
| Get shipment | GET | `/orders/{orderId}/shipments/{id}` | |
| Update shipment | PATCH | `/orders/{orderId}/shipments/{id}` | Tracking info |

### Recurring

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create customer | POST | `/customers` | ✅ Supported |
| List customers | GET | `/customers` | Not yet supported |
| Get customer | GET | `/customers/{id}` | ✅ Supported |
| Update customer | PATCH | `/customers/{id}` | Not yet supported |
| Delete customer | DELETE | `/customers/{id}` | Not yet supported |
| Create customer payment | POST | `/customers/{id}/payments` | ✅ Via Billable |
| List customer payments | GET | `/customers/{id}/payments` | Not yet supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create mandate | POST | `/customers/{customerId}/mandates` | Auto via first payment |
| List mandates | GET | `/customers/{customerId}/mandates` | Not yet supported |
| Get mandate | GET | `/customers/{customerId}/mandates/{id}` | ✅ Supported |
| Revoke mandate | DELETE | `/customers/{customerId}/mandates/{id}` | Not yet supported |

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create subscription | POST | `/customers/{customerId}/subscriptions` | ✅ Supported |
| List subscriptions | GET | `/customers/{customerId}/subscriptions` | Not yet supported |
| Get subscription | GET | `/customers/{customerId}/subscriptions/{id}` | ✅ Supported |
| Update subscription | PATCH | `/customers/{customerId}/subscriptions/{id}` | Not yet supported |
| Cancel subscription | DELETE | `/customers/{customerId}/subscriptions/{id}` | ✅ Supported |
| List all subscriptions | GET | `/subscriptions` | Not yet supported |
| List sub payments | GET | `/customers/{cId}/subscriptions/{sId}/payments` | Not yet supported |

### Mollie Connect (OAuth)

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Generate tokens | POST | `/oauth2/tokens` | OAuth flow |
| Revoke tokens | DELETE | `/oauth2/tokens` | OAuth flow |
| List permissions | GET | `/permissions` | OAuth scope check |
| Get permission | GET | `/permissions/{id}` | OAuth scope check |
| Get organization | GET | `/organizations/{id}` | Account info |
| Get current org | GET | `/organizations/me` | Account info |
| Get partner status | GET | `/organizations/{id}/partner-status` | Partner info |
| Create profile | POST | `/profiles` | Multi-profile management |
| List profiles | GET | `/profiles` | |
| Get profile | GET | `/profiles/{id}` | |
| Update profile | PATCH | `/profiles/{id}` | |
| Delete profile | DELETE | `/profiles/{id}` | |
| Get current profile | GET | `/profiles/me` | |
| Get onboarding status | GET | `/onboarding/v1/status` | Partner onboarding |
| Submit onboarding | POST | `/onboarding/v1/submit-data` | Partner onboarding |
| List capabilities | GET | `/capabilities` | Account capabilities |
| List clients | GET | `/clients` | Partner clients |
| Get client | GET | `/clients/{id}` | Partner clients |
| Create client link | POST | `/client-links` | Partner onboarding |
| Create balance transfer | POST | `/balance-transfers` | Platform payouts |
| List transfers | GET | `/balance-transfers` | |
| Get transfer | GET | `/balance-transfers/{id}` | |

### Business Operations

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| List balances | GET | `/balances` | Account balances |
| Get balance | GET | `/balances/{id}` | |
| Get primary balance | GET | `/balances/primary` | |
| Get balance report | GET | `/balances/{id}/report` | Detailed report |
| List transactions | GET | `/balances/{id}/transactions` | Balance movements |
| List settlements | GET | `/settlements` | Bank payouts |
| Get settlement | GET | `/settlements/{id}` | |
| Get open settlement | GET | `/settlements/open` | Current accumulating |
| Get next settlement | GET | `/settlements/next` | Upcoming payout |
| Settlement payments | GET | `/settlements/{id}/payments` | Included payments |
| Settlement captures | GET | `/settlements/{id}/captures` | Included captures |
| Settlement refunds | GET | `/settlements/{id}/refunds` | Included refunds |
| Settlement chargebacks | GET | `/settlements/{id}/chargebacks` | Included chargebacks |
| List invoices | GET | `/invoices` | Mollie billing invoices |
| Get invoice | GET | `/invoices/{id}` | |

### Revenue Collection

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create sales invoice | POST | `/sales-invoices` | Issue invoices to customers |
| List sales invoices | GET | `/sales-invoices` | |
| Get sales invoice | GET | `/sales-invoices/{id}` | |
| Update sales invoice | PATCH | `/sales-invoices/{id}` | |
| Delete sales invoice | DELETE | `/sales-invoices/{id}` | |

### Webhooks Management

| Endpoint | Method | Path | Notes |
|---|---|---|---|
| Create webhook | POST | `/webhooks` | Register webhook URLs |
| List webhooks | GET | `/webhooks` | |
| Get webhook | GET | `/webhooks/{id}` | |
| Update webhook | PATCH | `/webhooks/{id}` | |
| Delete webhook | DELETE | `/webhooks/{id}` | |
| Test webhook | POST | `/webhooks/{id}/tests` | |
| Get webhook event | GET | `/webhook-events/{id}` | |

---

## Coverage Gap Analysis

### Currently Supported (v0.4.0)

**Full support:** Customers (create/get), Payments (create oneoff/first/recurring, get), Subscriptions (create/cancel/get), Mandates (get), Refunds (create/get), Webhook handling (tr_/sub_/re_)

### Not Yet Supported

**Total Mollie API endpoints:** ~120+
**Currently supported operations:** ~15
**Coverage:** ~12%

### Categorized by Priority

**P0 — Critical for any SaaS app:**
- Payment Methods listing (every checkout needs this)
- Chargebacks (financial risk without it)
- Payment `authorized` state + captures (Klarna/BNPL)
- Payment update and cancel

**P1 — High value:**
- Payment Links (invoicing use case)
- Refund cancel, list operations
- Customer update/delete
- Subscription update, list operations
- Mandate list, revoke

**P2 — E-commerce:**
- Orders API (full CRUD)
- Order Lines management
- Shipments
- Order refunds

**P3 — Business operations:**
- Settlements (reconciliation)
- Balances (treasury)
- Invoices (billing)
- Sales Invoices (revenue collection)

**P4 — Platform/Admin:**
- Profiles
- Organizations
- Terminals
- Apple Pay sessions

**P5 — Mollie Connect (deferred):**
- OAuth token management
- Permissions
- Onboarding
- Client Links
- Capabilities
- Balance Transfers

---

## Key Architecture Findings

### 1. Webhook ID Prefix Gap (Critical)

The current `MOLLIE_ID_FORMAT` regex `/\A(tr|sub|re)_[a-zA-Z0-9]+\z/` silently rejects all new resource type webhooks. Mollie ID prefixes discovered:

| Prefix | Resource | Sends Webhooks? |
|---|---|---|
| `tr_` | Payment | ✅ Yes |
| `sub_` | Subscription | ✅ Yes |
| `re_` | Refund | ✅ Yes |
| `ord_` | Order | ✅ Yes |
| `stl_` | Settlement | ✅ Yes |
| `pl_` | Payment Link | ❌ No (via `tr_`) |
| `chb_` | Chargeback | ❌ No (via `tr_`) |
| `cpt_` | Capture | ❌ No (synchronous) |
| `shp_` | Shipment | ❌ No (via `ord_`) |
| `bal_` | Balance | ❌ No |
| `inv_` | Invoice | ❌ No |

### 2. Chargebacks Are Invisible (Critical)

Chargebacks don't trigger separate webhooks. They arrive embedded in payment objects via `tr_` webhooks. The payment status stays "paid" — only `amountChargedBack` changes. Current `previous_status` check will never detect them.

### 3. Captures Are Synchronous

Mollie does not send webhooks for captures. Captures are created via API call and the payment status eventually changes to "paid" via a subsequent `tr_` webhook. No separate model needed — just a Billable method.

### 4. Payment Links Break Customer Assumption

Payment links can be created without a customer. When paid, the resulting payment has no `customer_id`. Current `Payment.record_from_mollie` requires a customer — payments from anonymous payment links will be discarded.

### 5. Orders Are a Different Domain

Orders involve lines, shipments, addresses, and a different lifecycle. They need a separate `Orderable` concern rather than overloading `Billable`.

### 6. Settlements Are Account-Level

Settlements have no customer association. They need a different notification mechanism — `ActiveSupport::Notifications` or a configurable callback.

### 7. Mollie Connect Is Architecturally Invasive

OAuth multi-tenant changes every API call from using the global `Mollie::Client` to per-request token passing. Must be designed as a separate effort.

---

## Mollie SDK Coverage (mollie-api-ruby v4.19.0+)

The `mollie-api-ruby` gem provides Ruby SDK classes for most API resources:

| SDK Class | MolliePay Model |
|---|---|
| `Mollie::Payment` | `MolliePay::Payment` ✅ |
| `Mollie::Customer` | `MolliePay::Customer` ✅ |
| `Mollie::Customer::Subscription` | `MolliePay::Subscription` ✅ |
| `Mollie::Customer::Mandate` | `MolliePay::Mandate` ✅ |
| `Mollie::Refund` | `MolliePay::Refund` ✅ |
| `Mollie::Method` | Not yet modeled |
| `Mollie::Payment::Chargeback` | Not yet modeled |
| `Mollie::Payment::Capture` | Not needed (sync operation) |
| `Mollie::PaymentLink` | Not yet modeled |
| `Mollie::Order` | Not yet modeled |
| `Mollie::Order::Line` | Not yet modeled |
| `Mollie::Order::Shipment` | Not yet modeled |
| `Mollie::Settlement` | Not yet modeled |
| `Mollie::Balance` | Not yet modeled |
| `Mollie::Invoice` | Not yet modeled |
| `Mollie::Profile` | Not yet modeled |
| `Mollie::Organization` | Not yet modeled |
| `Mollie::Terminal` | Not yet modeled |

---

## Payment Status Lifecycle

```
open → paid
open → canceled
open → expired
open → failed
open → authorized → paid (via capture)
authorized → canceled (via release)
```

Payment amount fields:
- `amount` — original payment amount
- `amountRefunded` — total refunded
- `amountRemaining` — amount minus refunds
- `amountCaptured` — total captured (for authorized payments)
- `amountChargedBack` — total charged back

---

## Order Status Lifecycle

```
created → paid
created → authorized → paid (via shipment/capture)
created → canceled
created → expired
paid → shipping → completed
authorized → shipping → completed
any → canceled (partial cancel of lines possible)
```

---

## Recommendations

1. **Start with Phase 1 (Foundation)** — webhook infrastructure and authorized state. Everything else depends on this.
2. **Phase 2 (Chargebacks + Captures)** delivers the highest business value with moderate effort.
3. **Phase 3 (Payment Links)** enables invoicing workflows — a top SaaS use case.
4. **Phase 4 (Orders)** is the largest effort and serves e-commerce more than SaaS. Consider deferring.
5. **Phase 5 (Read-only)** is low effort, high completeness.
6. **Phase 6 (Connect)** is a separate project. Do not start it as part of this work.
