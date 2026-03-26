---
title: "docs: Add SEPA mandate consent and compliance documentation"
type: feat
status: active
date: 2026-03-26
---

# docs: Add SEPA mandate consent and compliance documentation

## Overview

Add comprehensive documentation about SEPA Direct Debit mandate consent requirements for `mollie_create_mandate`. Host app developers using direct mandate creation (bypassing Mollie's checkout) are legally responsible for collecting customer authorization, displaying mandate text, and maintaining consent records. This is currently undocumented.

## Problem Frame

PR #83 added `mollie_create_mandate` for direct SEPA DD mandate creation. Unlike `mollie_pay_first` (where Mollie's checkout handles consent and SCA), the direct API path places the full legal compliance burden on the host app. Without documentation, developers may create mandates without proper customer authorization, exposing themselves to dispute risk and potential regulatory issues.

The EPC SEPA DD Core Rulebook requires: signed mandate with specific text, debtor IBAN and name, creditor identifier, signature date, and immutable storage for 36+ months. Web collection requires displaying the full mandate text and recording consent proof (timestamp, IP, user agent).

## Requirements Trace

- R1. Create `docs/mandates.md` comprehensive guide covering both mandate creation paths
- R2. Document the legally required EPC mandate authorization text
- R3. Document what the host app must collect, display, and store for direct mandate creation
- R4. Document web signature collection best practices and legal standing
- R5. Update README.md with mandate create/revoke examples and compliance pointer
- R6. Update AGENTS.md with new Billable methods from PR #83
- R7. Add `signatureDate` recommendation to `mollie_create_mandate` — pass it through to Mollie as evidence of consent timing

## Scope Boundaries

- No enforcement of consent collection in code — the gem documents requirements, host apps implement consent flows
- No mandate text template generator — provide the text, host apps render it
- No consent storage model — document what to store, host apps choose how

## Key Technical Decisions

- **Dedicated `docs/mandates.md`**: Follows the existing pattern of feature-area docs (`webhooks.md`, `testing.md`). Mandates deserve their own guide given the legal complexity.
- **Two-path documentation**: Clearly distinguish `mollie_pay_first` (recommended, PSP handles consent) from `mollie_create_mandate` (direct, merchant handles consent). Most developers should use the first path.
- **`signatureDate` pass-through**: The Mollie API accepts `signatureDate` on mandate creation. Document and recommend passing it as evidence of when consent was collected.

## Implementation Units

- [ ] **Unit 1: Create `docs/mandates.md` compliance guide**

  **Goal:** Comprehensive guide covering SEPA DD mandate requirements, both creation paths, web consent collection, and record-keeping obligations.

  **Requirements:** R1, R2, R3, R4

  **Files:**
  - Create: `docs/mandates.md`

  **Approach:**
  - Section 1: Overview of SEPA DD mandates and why authorization matters
  - Section 2: Two paths compared (first payment vs direct creation) with recommendation
  - Section 3: Legal requirements for direct mandate creation — EPC mandate text (verbatim), required fields, creditor identifier info (Mollie's CI: NL08ZZZ502057730000)
  - Section 4: Collecting consent on the web — display mandate text, explicit acceptance, record proof (timestamp, IP, user agent, text version), store immutably 36+ months
  - Section 5: What to communicate to the customer — confirmation page or email with mandate copy, pre-notification before debits (14 days standard)
  - Section 6: Code examples for both paths
  - Section 7: Record-keeping summary table
  - Include the standard EPC authorization text template with placeholder markers

  **Patterns to follow:**
  - `docs/webhooks.md` for guide structure and depth
  - `docs/tutorial.md` callout box pattern for warnings

  **Verification:**
  - Guide covers both mandate creation paths with clear recommendation
  - EPC mandate text is included verbatim
  - Host app obligations are concrete and actionable

- [ ] **Unit 2: Update README.md and AGENTS.md**

  **Goal:** Document `mollie_create_mandate`, `mollie_revoke_mandate`, `mollie_update_customer`, `mollie_delete_customer` in the public API references with a compliance pointer.

  **Requirements:** R5, R6

  **Files:**
  - Modify: `README.md`
  - Modify: `AGENTS.md`

  **Approach:**
  - README: Add "Mandates" section after subscriptions with create/revoke examples, prominent note linking to `docs/mandates.md` for compliance requirements
  - README: Add "Customer management" section with update/delete examples
  - AGENTS.md: Add all four new Billable methods to the public methods list
  - AGENTS.md: Add `mollie_create_mandate`, `mollie_revoke_mandate`, `mollie_update_customer`, `mollie_delete_customer` with parameter signatures
  - Both: Include a brief warning that `mollie_create_mandate` requires prior customer consent

  **Patterns to follow:**
  - README payment methods section for code examples
  - AGENTS.md Billable methods list format

  **Verification:**
  - All new Billable methods are documented in both files
  - Compliance warning is visible near `mollie_create_mandate`

- [ ] **Unit 3: Add `signature_date` parameter and documentation to `mollie_create_mandate`**

  **Goal:** Document and recommend the `signature_date` parameter on `mollie_create_mandate` as evidence of consent timing.

  **Requirements:** R7

  **Files:**
  - Modify: `app/models/mollie_pay/billable.rb` (add `signature_date:` named parameter)
  - Modify: `test/models/mollie_pay/billable_test.rb`

  **Approach:**
  - Add `signature_date: nil` parameter to `mollie_create_mandate`
  - When provided, pass as `signatureDate: signature_date.to_s` to Mollie API
  - Document in the mandates guide that passing `signature_date: Date.today` is recommended
  - Test that `signatureDate` is forwarded to the Mollie API when provided

  **Patterns to follow:**
  - `mollie_subscribe` for optional parameter handling (e.g., `start_date`)

  **Test scenarios:**
  - `mollie_create_mandate` forwards `signatureDate` to Mollie when provided
  - `mollie_create_mandate` omits `signatureDate` when not provided

  **Verification:**
  - Parameter is accepted and forwarded correctly
  - Documented in mandates guide with recommendation

## Sources & References

- EPC SEPA DD Core Rulebook: https://www.europeanpaymentscouncil.eu/what-we-do/epc-payment-schemes/sepa-direct-debit
- Mollie Create Mandate: https://docs.mollie.com/reference/create-mandate
- Mollie Creditor Identifier: NL08ZZZ502057730000
- Mollie Recurring Payments: https://docs.mollie.com/docs/recurring-payments
- eIDAS Regulation (EU No 910/2014) on electronic signatures
- GoCardless Mandate Contents: https://gocardless.com/en-us/guides/sepa/mandate-contents/
- Related PR: #83
- Related issue: #78
