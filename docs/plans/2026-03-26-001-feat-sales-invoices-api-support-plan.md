---
title: "feat: Add Sales Invoices API support (beta)"
type: feat
status: completed
date: 2026-03-26
---

# feat: Add Sales Invoices API support (beta)

## Overview

Add support for Mollie's Sales Invoices API (beta), enabling host apps to create, retrieve, update, delete, and list sales invoices through the MolliePay gem. This follows the class-method-only pattern (like `payment_methods`) — no local ActiveRecord model, since there's no per-resource webhook support for sales invoices via API keys.

## Problem Frame

Mollie's Sales Invoices API lets merchants create and send invoices to their customers. The `mollie-api-ruby` SDK does not have a `SalesInvoice` class, and the existing `Mollie::Invoice` represents Mollie's fee invoices to the merchant — a completely different resource. Host apps currently have no way to use this API through mollie_pay.

Related: GitHub issue #69

## Requirements Trace

- R1. Provide a `Mollie::SalesInvoice` SDK extension class that maps to the `/v2/sales-invoices` endpoint
- R2. Expose CRUD + list operations as class methods on the `MolliePay` module
- R3. Add Billable convenience methods that auto-populate recipient from the billable model
- R4. Handle amount conversion (cents → Mollie format) consistently with existing patterns
- R5. Handle nested hash key camelization for recipient, emailDetails, paymentDetails
- R6. Mark the feature as beta/experimental in documentation
- R7. Follow existing test patterns (Minitest, stub-based, no real HTTP)

## Scope Boundaries

- No local ActiveRecord model or migration — the issue recommends deferring this until webhook support is available via API keys
- No webhook/event processing for sales invoices — `ProcessWebhookEventJob` remains a logger for now
- No PDF download helper — the PDF URL is available in the response `_links`
- No polling/background sync — host apps check status on demand
- No OAuth/Mollie Connect integration (that's issue #55)

## Context & Research

### Relevant Code and Patterns

- `lib/mollie_pay.rb` — class-method-only pattern (`payment_methods`, `payment_method`)
- `app/models/mollie_pay/billable.rb` — convenience delegation (`mollie_payment_methods`)
- `test/lib/mollie_pay/payment_methods_test.rb` — test pattern for class-method features
- `mollie-api-ruby` `Mollie::Base` — SDK base class with CRUD, derives API path from class name
- `mollie-api-ruby` `Mollie::Client#perform_http_call` — camelizes top-level keys, but only recurses into `CAMELIZE_NESTED` keys (includes `lines` but not `recipient`, `email_details`, etc.)
- `lib/mollie_pay/errors.rb` — custom error classes

### Institutional Learnings

- From `docs/solutions/integration-issues/mollie-chargeback-model-api-discovery.md`: Always verify API responses against live data, use camelCase in test fixtures, check `attributes` hash for fields not exposed via `attr_accessor`

## Key Technical Decisions

- **SDK extension in mollie_pay, not upstream PR**: Create `Mollie::SalesInvoice` within the gem's `lib/` directory. The SDK doesn't have this class and an upstream PR is a separate effort. This keeps us unblocked. The class inherits from `Mollie::Base` and overrides `resource_name` to return `"sales-invoices"` (hyphenated, matching the API endpoint).

- **Deep camelization for nested hashes**: The SDK's `camelize_keys` only recurses into keys listed in `CAMELIZE_NESTED` (includes `lines` but not `recipient`, `email_details`, `payment_details`). The `MolliePay` module methods will accept Ruby-idiomatic snake_case hashes and convert nested objects to camelCase before passing to the SDK. This keeps the public API clean.

- **Class methods on MolliePay module**: Following the `payment_methods` pattern exactly — `MolliePay.create_sales_invoice(...)`, `MolliePay.sales_invoice(id)`, `MolliePay.sales_invoices`, `MolliePay.update_sales_invoice(id, ...)`, `MolliePay.delete_sales_invoice(id)`.

- **Billable convenience**: `mollie_create_sales_invoice(...)` that auto-populates recipient fields from the billable model, and `mollie_sales_invoices` / `mollie_sales_invoice(id)` that delegate to `MolliePay`.

- **Amount handling**: Accept cents integers in the public API, convert to Mollie format at the API boundary using the same `format("%.2f", cents / 100.0)` pattern. Line item `unit_price` follows the same conversion.

## Open Questions

### Resolved During Planning

- **Where does the SDK extension live?** In `lib/mollie/sales_invoice.rb`, loaded by `lib/mollie_pay.rb`. This mirrors how a gem would extend another gem's namespace — clean and conventional.
- **How to handle the hyphenated API path?** Override `self.resource_name` on `Mollie::SalesInvoice` to return `"sales-invoices"` since the SDK's default derivation would produce `"salesinvoices"`.

### Deferred to Implementation

- **Exact attr_accessor list**: The issue documents the response fields, but the final list should be verified against the actual API response structure during implementation.
- **Whether `Util.camelize_keys` handles `lines` correctly for sales invoice line items**: The `lines` key IS in `CAMELIZE_NESTED`, so inner keys like `vat_rate` should be camelized. Verify during testing.

## Implementation Units

- [ ] **Unit 1: Mollie::SalesInvoice SDK extension class**

  **Goal:** Create a `Mollie::SalesInvoice` class that extends `Mollie::Base` and maps to the `/v2/sales-invoices` endpoint, providing CRUD + list operations via the SDK's standard patterns.

  **Requirements:** R1

  **Dependencies:** None

  **Files:**
  - Create: `lib/mollie/sales_invoice.rb`
  - Modify: `lib/mollie_pay.rb` (add require)
  - Test: `test/lib/mollie/sales_invoice_test.rb`

  **Approach:**
  - Inherit from `Mollie::Base`
  - Override `self.resource_name` to return `"sales-invoices"`
  - Add `attr_accessor` for all documented response fields (snake_case, as the SDK auto-converts)
  - Add status constants: `STATUS_DRAFT`, `STATUS_ISSUED`, `STATUS_PAID`, `STATUS_CANCELED`
  - Add status predicates: `draft?`, `issued?`, `paid?`, `canceled?`
  - Add link helpers: `pdf_url`, `payment_url` (extract from `_links` using `Mollie::Util.extract_url`)
  - Amount fields (`subtotal_amount`, `total_vat_amount`, `total_amount`, `amount_due`) should have setters that convert hashes to `Mollie::Amount` if present

  **Patterns to follow:**
  - `Mollie::Payment` in the SDK for attr_accessor structure and amount handling
  - `Mollie::Base` for CRUD pattern

  **Test scenarios:**
  - `resource_name` returns `"sales-invoices"`
  - Initializing from a response hash populates all attributes
  - Status predicates return correct booleans
  - `pdf_url` and `payment_url` extract correctly from `_links`
  - Class methods (`create`, `get`, `all`, `update`, `delete`) are inherited from Base and callable

  **Verification:**
  - `Mollie::SalesInvoice.resource_name` returns `"sales-invoices"`
  - A `Mollie::SalesInvoice` instance initializes cleanly from a camelCase API response hash

- [ ] **Unit 2: MolliePay module class methods for Sales Invoices**

  **Goal:** Add public class methods on the `MolliePay` module for all sales invoice operations, handling amount conversion and nested hash camelization.

  **Requirements:** R2, R4, R5

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/mollie_pay.rb`
  - Test: `test/lib/mollie_pay/sales_invoices_test.rb`

  **Approach:**
  - `MolliePay.create_sales_invoice(status:, recipient:, lines:, **options)` — converts line item amounts from cents, camelizes nested hashes, calls `Mollie::SalesInvoice.create`
  - `MolliePay.sales_invoice(id)` — calls `Mollie::SalesInvoice.get(id)`
  - `MolliePay.sales_invoices(**options)` — calls `Mollie::SalesInvoice.all(options)`
  - `MolliePay.update_sales_invoice(id, **attrs)` — calls `Mollie::SalesInvoice.update(id, attrs)`
  - `MolliePay.delete_sales_invoice(id)` — calls `Mollie::SalesInvoice.delete(id)`
  - Add a private `deep_camelize_keys` helper on the module for converting nested snake_case hashes to camelCase (needed because the SDK only camelizes top-level keys for non-CAMELIZE_NESTED keys)
  - Line item `unit_price` accepts cents integer and converts to Mollie amount format
  - `email_details` and `payment_details` hashes are deep-camelized

  **Patterns to follow:**
  - `MolliePay.payment_methods` / `MolliePay.payment_method` for structure
  - `mollie_amount` helper pattern for amount conversion

  **Test scenarios:**
  - `create_sales_invoice` passes correct camelCase params to SDK
  - Line item `unit_price` in cents is converted to Mollie amount format
  - `recipient` hash keys are camelized (e.g., `given_name` → `givenName`)
  - `email_details` hash keys are camelized (e.g., `subject` stays, but `email_details` → `emailDetails`)
  - `sales_invoice(id)` delegates to `Mollie::SalesInvoice.get`
  - `sales_invoices` delegates to `Mollie::SalesInvoice.all`
  - `update_sales_invoice` delegates to `Mollie::SalesInvoice.update`
  - `delete_sales_invoice` delegates to `Mollie::SalesInvoice.delete`
  - Options like `payment_term`, `vat_scheme`, `vat_mode`, `memo`, `metadata` are forwarded

  **Verification:**
  - All five methods exist and delegate correctly
  - Amount conversion matches existing pattern (cents → `{ currency: "EUR", value: "10.00" }`)
  - Nested hashes arrive at the SDK with correct camelCase keys

- [ ] **Unit 3: Billable concern convenience methods**

  **Goal:** Add convenience methods to the Billable concern that auto-populate recipient data from the billable model and delegate to `MolliePay` module methods.

  **Requirements:** R3, R4

  **Dependencies:** Unit 2

  **Files:**
  - Modify: `app/models/mollie_pay/billable.rb`
  - Modify: `test/models/mollie_pay/billable_test.rb`

  **Approach:**
  - `mollie_create_sales_invoice(lines:, status: "draft", **options)` — builds recipient hash from billable model attributes (name, email, and address if available), merges with any explicit `recipient:` override, delegates to `MolliePay.create_sales_invoice`
  - `mollie_sales_invoices(**options)` — delegates to `MolliePay.sales_invoices`
  - `mollie_sales_invoice(id)` — delegates to `MolliePay.sales_invoice(id)`
  - Recipient auto-population: check `respond_to?` for `:name`, `:email`, `:organization_name` etc., building a consumer or business recipient hash based on available attributes. The explicit `recipient:` parameter always wins.

  **Patterns to follow:**
  - `mollie_payment_methods(**options)` delegation pattern
  - `create_mollie_customer_on_mollie` for `respond_to?` checks on billable model

  **Test scenarios:**
  - `mollie_create_sales_invoice` auto-populates recipient from billable model
  - Explicit `recipient:` overrides auto-populated values
  - `mollie_sales_invoices` delegates correctly
  - `mollie_sales_invoice(id)` delegates correctly
  - Line items with `unit_price` in cents are passed through correctly

  **Verification:**
  - Billable convenience methods exist and delegate to `MolliePay` module
  - Recipient auto-population works for models with name/email attributes

- [ ] **Unit 4: Test helper stubs and documentation**

  **Goal:** Add test helper methods for sales invoices following the existing stub pattern, and add usage examples to the README.

  **Requirements:** R6, R7

  **Dependencies:** Units 1-3

  **Files:**
  - Modify: `lib/mollie_pay/test_helper.rb`
  - Create: `lib/mollie_pay/test_fixtures/sales_invoice.json`
  - Modify: `README.md` (sales invoices section)

  **Approach:**
  - Add `fake_mollie_sales_invoice` helper returning an OpenStruct with standard fields
  - Add `stub_mollie_sales_invoice_create` and `stub_mollie_sales_invoice_get` helpers
  - Add WebMock helpers: `webmock_mollie_sales_invoice_create`, `webmock_mollie_sales_invoice_get`
  - Create `sales_invoice.json` fixture with camelCase keys matching the real API response
  - Add a "Sales Invoices (beta)" section to README with create, get, list, update, delete examples
  - Mark the section as beta/experimental

  **Patterns to follow:**
  - Existing test helpers in `lib/mollie_pay/test_helper.rb`
  - Existing JSON fixtures in `lib/mollie_pay/test_fixtures/`
  - README structure for existing features

  **Test scenarios:**
  - Test helpers produce valid fake objects
  - JSON fixture has camelCase keys and includes all documented response fields

  **Verification:**
  - All existing tests still pass
  - New test helpers are usable in a test context
  - README documents the beta feature with clear examples

## System-Wide Impact

- **Interaction graph:** No callbacks, middleware, or observers affected. The feature is additive — new class methods on `MolliePay` and new methods on `Billable`. No existing behavior changes.
- **Error propagation:** SDK errors (`Mollie::RequestError`, `Mollie::ResourceNotFoundError`) propagate naturally from `Mollie::SalesInvoice` through the `MolliePay` module methods to the caller. No custom error wrapping needed.
- **State lifecycle risks:** None — no local model, no state to manage. All state lives on Mollie's side.
- **API surface parity:** The `ProcessWebhookEventJob` currently logs all events. When sales invoice events arrive via next-gen webhooks, they will be logged but not processed. This is acceptable for now and documented as a future enhancement.
- **Integration coverage:** Unit tests with stubs are sufficient since there's no local state. The SDK extension class is tested for correct API path generation and attribute mapping.

## Risks & Dependencies

- **Beta API instability:** The Sales Invoices API is in beta. Fields, behavior, or endpoints may change. The feature should be clearly marked as beta.
- **SDK key camelization gap:** The `camelize_keys` method in the SDK doesn't recurse into `recipient` or `email_details` keys. The `deep_camelize_keys` helper in `MolliePay` handles this, but if the SDK adds `SalesInvoice` support natively in the future, we should migrate to it and remove our extension.
- **No webhook-driven sync:** Without webhooks, invoice payment status must be checked on demand. Host apps need to poll or check manually. This is an intentional scope boundary.

## Sources & References

- Related issue: #69
- Mollie Sales Invoices API: https://docs.mollie.com/reference/create-sales-invoice
- Mollie Connect / OAuth: #55 (future dependency for webhook support)
- `mollie-api-ruby` SDK: https://github.com/mollie/mollie-api-ruby
