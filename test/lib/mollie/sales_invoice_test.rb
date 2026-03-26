require "test_helper"

class Mollie::SalesInvoiceTest < ActiveSupport::TestCase
  test "resource_name returns sales-invoices" do
    assert_equal "sales-invoices", Mollie::SalesInvoice.resource_name
  end

  test "initializes from API response hash" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)

    assert_equal "invoice_abc123", invoice.id
    assert_equal "issued", invoice.status
    assert_equal "INV-0000001", invoice.invoice_number
    assert_equal "profile_xyz", invoice.profile_id
    assert_equal "customer-xyz-0123", invoice.recipient_identifier
    assert_equal "30 days", invoice.payment_term
    assert_equal "standard", invoice.vat_scheme
    assert_equal "exclusive", invoice.vat_mode
    assert_equal "Thank you!", invoice.memo
    assert_equal false, invoice.is_e_invoice
  end

  test "status predicates" do
    draft = Mollie::SalesInvoice.new("status" => "draft")
    assert draft.draft?
    assert_not draft.issued?
    assert_not draft.paid?
    assert_not draft.canceled?

    issued = Mollie::SalesInvoice.new("status" => "issued")
    assert issued.issued?
    assert_not issued.draft?

    paid = Mollie::SalesInvoice.new("status" => "paid")
    assert paid.paid?

    canceled = Mollie::SalesInvoice.new("status" => "canceled")
    assert canceled.canceled?
  end

  test "amount fields are converted to Mollie::Amount" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)

    assert_instance_of Mollie::Amount, invoice.subtotal_amount
    assert_equal BigDecimal("89.00"), invoice.subtotal_amount.value

    assert_instance_of Mollie::Amount, invoice.total_vat_amount
    assert_equal BigDecimal("18.69"), invoice.total_vat_amount.value

    assert_instance_of Mollie::Amount, invoice.total_amount
    assert_equal BigDecimal("107.69"), invoice.total_amount.value

    assert_instance_of Mollie::Amount, invoice.amount_due
    assert_equal BigDecimal("107.69"), invoice.amount_due.value
  end

  test "timestamp fields are parsed to Time" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)

    assert_instance_of Time, invoice.created_at
    assert_instance_of Time, invoice.issued_at
    assert_instance_of Time, invoice.due_at
    assert_nil invoice.paid_at
  end

  test "recipient is converted to OpenStruct" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)

    assert_instance_of OpenStruct, invoice.recipient
    assert_equal "consumer", invoice.recipient.type
    assert_equal "Jane", invoice.recipient.given_name
    assert_equal "Doe", invoice.recipient.family_name
  end

  test "metadata is converted to OpenStruct" do
    invoice = Mollie::SalesInvoice.new(
      "metadata" => { "order_id" => "ord_123" }
    )

    assert_instance_of OpenStruct, invoice.metadata
    assert_equal "ord_123", invoice.metadata.order_id
  end

  test "pdf_url extracts from links" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)
    assert_equal "https://api.mollie.com/v2/sales-invoices/invoice_abc123/pdf", invoice.pdf_url
  end

  test "payment_url extracts from links" do
    invoice = Mollie::SalesInvoice.new(api_response_hash)
    assert_equal "https://pay.mollie.com/invoice/abc123", invoice.payment_url
  end

  test "pdf_url returns nil when no links" do
    invoice = Mollie::SalesInvoice.new("status" => "draft")
    assert_nil invoice.pdf_url
  end

  test "CRUD methods are inherited from Base" do
    assert_respond_to Mollie::SalesInvoice, :create
    assert_respond_to Mollie::SalesInvoice, :get
    assert_respond_to Mollie::SalesInvoice, :all
    assert_respond_to Mollie::SalesInvoice, :update
    assert_respond_to Mollie::SalesInvoice, :delete
  end

  private

    def api_response_hash
      {
        "id" => "invoice_abc123",
        "profile_id" => "profile_xyz",
        "status" => "issued",
        "invoice_number" => "INV-0000001",
        "recipient_identifier" => "customer-xyz-0123",
        "recipient" => {
          "type" => "consumer",
          "given_name" => "Jane",
          "family_name" => "Doe",
          "email" => "jane@example.com"
        },
        "lines" => [
          {
            "description" => "Monthly subscription",
            "quantity" => 1,
            "vat_rate" => "21.00",
            "unit_price" => { "currency" => "EUR", "value" => "89.00" }
          }
        ],
        "payment_term" => "30 days",
        "vat_scheme" => "standard",
        "vat_mode" => "exclusive",
        "memo" => "Thank you!",
        "is_e_invoice" => false,
        "subtotal_amount" => { "currency" => "EUR", "value" => "89.00" },
        "total_vat_amount" => { "currency" => "EUR", "value" => "18.69" },
        "total_amount" => { "currency" => "EUR", "value" => "107.69" },
        "amount_due" => { "currency" => "EUR", "value" => "107.69" },
        "created_at" => "2026-03-26T10:00:00+00:00",
        "issued_at" => "2026-03-26T10:00:00+00:00",
        "due_at" => "2026-04-25T10:00:00+00:00",
        "_links" => {
          "self" => { "href" => "https://api.mollie.com/v2/sales-invoices/invoice_abc123" },
          "pdf_link" => { "href" => "https://api.mollie.com/v2/sales-invoices/invoice_abc123/pdf" },
          "invoice_payment" => { "href" => "https://pay.mollie.com/invoice/abc123" }
        }
      }
    end
end
