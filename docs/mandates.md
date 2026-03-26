# SEPA Direct Debit Mandates

A SEPA Direct Debit mandate is a legal authorization from a customer allowing you
to debit their bank account. MolliePay supports two ways to create mandates, each
with different compliance obligations.

## Two Paths to Mandates

### Path 1: First Payment (Recommended)

Use `mollie_pay_first` to create a payment with `sequenceType: "first"`. The
customer is redirected to Mollie's checkout, where their bank authenticates them
with Strong Customer Authentication (SCA). On success, Mollie automatically
creates a `directdebit` mandate.

```ruby
payment = current_organization.mollie_pay_first(
  amount: 100, description: "Activation fee"
)
redirect_to payment.checkout_url
```

**This is the recommended approach for most applications.** Mollie's checkout
handles consent display, bank authentication, and mandate creation. Your
compliance obligations are minimal.

### Path 2: Direct Mandate Creation

Use `mollie_create_mandate` to create a SEPA DD mandate directly from an IBAN.
This is useful for migrating mandates from another provider or when you already
have a bank relationship with the customer.

```ruby
mandate = current_organization.mollie_create_mandate(
  method: "directdebit",
  consumer_name: "Jane Doe",
  consumer_account: "NL55INGB0000000000",
  signature_date: Date.today
)
```

> **You are legally responsible for collecting customer authorization before
> calling this method.** Mollie's checkout is not involved — there is no bank
> authentication or consent display. See the requirements below.

### Comparison

| Aspect | First Payment | Direct Creation |
|--------|--------------|-----------------|
| Bank authentication (SCA) | Yes — handled by bank | No |
| Consent text display | Handled by Mollie checkout | Your responsibility |
| Proof of consent | Bank authentication | You must collect and store |
| Dispute risk | Lower (authorized mandate) | Higher (you must prove consent) |
| Best for | Most SaaS applications | Mandate migrations, pre-existing relationships |
| Method | `mollie_pay_first` | `mollie_create_mandate` |

## Legal Requirements for Direct Mandate Creation

When using `mollie_create_mandate`, the European Payments Council (EPC) SEPA
Direct Debit Core Rulebook requires you to:

### 1. Display the Mandate Authorization Text

You must show the customer the following standard text (or equivalent in their
language) before they authorize the mandate:

> By signing this mandate form, you authorise (A) **{YOUR COMPANY NAME}** to
> send instructions to your bank to debit your account and (B) your bank to
> debit your account in accordance with the instructions from **{YOUR COMPANY
> NAME}**.
>
> As part of your rights, you are entitled to a refund from your bank under the
> terms and conditions of your agreement with your bank. A refund must be
> claimed within 8 weeks starting from the date on which your account was
> debited. Your rights are explained in a statement that you can obtain from
> your bank.

Replace `{YOUR COMPANY NAME}` with your business name. Note that Mollie acts as
the creditor of record (Creditor Identifier: `NL08ZZZ502057730000`), so Mollie's
name appears on the customer's bank statement.

### 2. Collect Required Information

| Field | Description | Required |
|-------|-------------|----------|
| Full name | Account holder name | Yes |
| IBAN | International Bank Account Number | Yes |
| Explicit consent | Customer actively accepts the mandate | Yes |
| BIC | Bank Identifier Code | Optional (derived from IBAN) |

### 3. Record Proof of Consent

When the customer accepts the mandate on your website, record:

- **Timestamp** — exact date and time of acceptance
- **IP address** — the customer's IP at time of acceptance
- **User agent** — browser identification string
- **Mandate text version** — the exact text the customer agreed to
- **Customer identifiers** — name, email, account used

Pass the consent date to Mollie via the `signature_date` parameter:

```ruby
mandate = current_organization.mollie_create_mandate(
  method: "directdebit",
  consumer_name: "Jane Doe",
  consumer_account: "NL55INGB0000000000",
  signature_date: Date.today
)
```

### 4. Store Records

Mandate consent records must be stored for:

- **Active mandates**: entire duration the mandate is active
- **After last collection**: at least **36 months** after the final debit
- **Best practice**: retain for **10 years** (varies by national law)

Records must be stored in a way that prevents modification (integrity
protection). If a customer disputes a debit, you must be able to produce
the mandate as evidence.

### 5. Communicate to the Customer

After the customer accepts:

1. **Confirmation**: Show the mandate details on a confirmation page or send
   via email immediately
2. **Pre-notification**: Notify the customer at least **14 calendar days** before
   each debit (can be shortened to a minimum of 2 days by written agreement
   with the customer)

## Collecting Consent on the Web

### Recommended Approach

Display the full mandate text on a dedicated form page. The customer fills in
their name and IBAN, reads the authorization text, and submits the form. The
form submission constitutes their consent.

A well-designed consent form includes:

1. IBAN and name input fields
2. The full EPC mandate authorization text (visible, not behind a link)
3. A clear submit button with text like "Authorize Direct Debit"
4. Recording of timestamp, IP, and user agent on submission

### Is a Checkbox Sufficient?

A simple checkbox is a "Simple Electronic Signature" (SES) under the EU's eIDAS
Regulation. For SEPA Core Direct Debit (consumer-facing), this is accepted in
practice when combined with visible mandate text and proper record-keeping.

For SEPA B2B Direct Debit (business-to-business), an Advanced Electronic
Signature (AES) or Qualified Electronic Signature (QES) is required. This is
beyond what a checkbox provides — consider a dedicated e-signature service.

### Legal Standing

Under eIDAS Regulation (EU No 910/2014), electronic signatures cannot be denied
legal effect solely because they are electronic. E-mandates collected via web
forms are valid across all 36 SEPA countries when they comply with the
requirements above.

The key factor in disputes is **evidence quality**, not signature type. A form
submission with timestamp, IP address, displayed mandate text, and stored consent
record is defensible. A mandate created with no consent evidence is not.

## Revoking Mandates

Customers can request mandate revocation at any time. Use `mollie_revoke_mandate`
to revoke on Mollie's side and update the local record:

```ruby
mandate = current_organization.mollie_mandate
current_organization.mollie_revoke_mandate(mandate)
```

This sets the mandate status to `invalid` locally and on Mollie. Any active
subscriptions using this mandate should be canceled separately.

## Quick Reference

| Obligation | First Payment | Direct Creation |
|------------|:------------:|:---------------:|
| Display mandate text | Mollie handles | You |
| Collect IBAN + name | Mollie handles | You |
| Record consent proof | Bank auth | You |
| Store records 36+ months | Recommended | Required |
| Pre-notify before debits | Recommended | Required |
| Send mandate copy | Mollie handles | You |

## References

- [EPC SEPA DD Mandate Requirements](https://www.europeanpaymentscouncil.eu/what-we-do/epc-payment-schemes/sepa-direct-debit/sdd-mandate)
- [Mollie Recurring Payments](https://docs.mollie.com/docs/recurring-payments)
- [Mollie Create Mandate API](https://docs.mollie.com/reference/create-mandate)
- [eIDAS Regulation (EU No 910/2014)](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=uriserv:OJ.L_.2014.257.01.0073.01.ENG)
