require "test_helper"

module MolliePay
  class SalesInvoiceTest < ActiveSupport::TestCase
    test "record_from_mollie creates new record" do
      customer = mollie_pay_customers(:acme)
      mollie_si = fake_mollie_si(
        id: "invoice_new123",
        status: "issued",
        invoice_number: "INV-0000001",
        recipient_identifier: "cust-xyz",
        memo: "Thank you",
        amount_value: BigDecimal("107.69"),
        amount_currency: "EUR",
        issued_at: Time.current,
        paid_at: nil,
        due_at: 30.days.from_now
      )

      invoice = SalesInvoice.record_from_mollie(mollie_si, customer)

      assert_equal "invoice_new123", invoice.mollie_id
      assert_equal "issued", invoice.status
      assert_equal "INV-0000001", invoice.invoice_number
      assert_equal 10769, invoice.amount
      assert_equal "EUR", invoice.currency
      assert_equal "cust-xyz", invoice.recipient_identifier
      assert_equal "Thank you", invoice.memo
    end

    test "record_from_mollie updates existing record on status change" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_sales_invoices(:acme_draft)

      mollie_si = fake_mollie_si(
        id: existing.mollie_id,
        status: "issued",
        invoice_number: "INV-0000002",
        recipient_identifier: "cust-abc",
        memo: "Updated",
        amount_value: BigDecimal("50.00"),
        amount_currency: "EUR",
        issued_at: Time.current,
        paid_at: nil,
        due_at: 30.days.from_now
      )

      SalesInvoice.record_from_mollie(mollie_si, customer)

      existing.reload
      assert_equal "issued", existing.status
      assert_equal "INV-0000002", existing.invoice_number
      assert_equal 5000, existing.amount
    end

    test "record_from_mollie fires on_mollie_sales_invoice_paid on transition" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_sales_invoices(:acme_issued)
      hook_called = false

      owner = customer.owner
      owner.define_singleton_method(:on_mollie_sales_invoice_paid) { |_si| hook_called = true }

      mollie_si = fake_mollie_si(
        id: existing.mollie_id,
        status: "paid",
        invoice_number: existing.invoice_number,
        recipient_identifier: existing.recipient_identifier,
        memo: existing.memo,
        amount_value: BigDecimal("107.69"),
        amount_currency: "EUR",
        issued_at: existing.issued_at,
        paid_at: Time.current,
        due_at: existing.due_at
      )

      SalesInvoice.record_from_mollie(mollie_si, customer)

      assert hook_called, "on_mollie_sales_invoice_paid should have been called"
    end

    test "record_from_mollie fires on_mollie_sales_invoice_issued on transition" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_sales_invoices(:acme_draft)
      hook_called = false

      owner = customer.owner
      owner.define_singleton_method(:on_mollie_sales_invoice_issued) { |_si| hook_called = true }

      mollie_si = fake_mollie_si(
        id: existing.mollie_id,
        status: "issued",
        invoice_number: "INV-0000003",
        recipient_identifier: "cust-xyz",
        memo: "Issued now",
        amount_value: BigDecimal("50.00"),
        amount_currency: "EUR",
        issued_at: Time.current,
        paid_at: nil,
        due_at: 30.days.from_now
      )

      SalesInvoice.record_from_mollie(mollie_si, customer)

      assert hook_called, "on_mollie_sales_invoice_issued should have been called"
    end

    test "record_from_mollie does NOT fire hooks when status unchanged" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_sales_invoices(:acme_issued)
      hook_called = false

      owner = customer.owner
      owner.define_singleton_method(:on_mollie_sales_invoice_issued) { |_si| hook_called = true }
      owner.define_singleton_method(:on_mollie_sales_invoice_paid) { |_si| hook_called = true }

      mollie_si = fake_mollie_si(
        id: existing.mollie_id,
        status: "issued",
        invoice_number: existing.invoice_number,
        recipient_identifier: existing.recipient_identifier,
        memo: "Updated memo",
        amount_value: BigDecimal("107.69"),
        amount_currency: "EUR",
        issued_at: existing.issued_at,
        paid_at: nil,
        due_at: existing.due_at
      )

      SalesInvoice.record_from_mollie(mollie_si, customer)

      assert_not hook_called, "No hooks should have been called when status unchanged"
    end

    test "record_from_mollie handles RecordNotUnique" do
      customer = mollie_pay_customers(:acme)
      existing = mollie_pay_sales_invoices(:acme_issued)

      mollie_si = fake_mollie_si(
        id: existing.mollie_id,
        status: "issued"
      )

      # Simulate a race condition by raising RecordNotUnique on update!
      SalesInvoice.stub(:find_or_initialize_by, ->(_) {
        raise ActiveRecord::RecordNotUnique, "duplicate"
      }) do
        result = SalesInvoice.record_from_mollie(mollie_si, customer)
        assert_equal existing.id, result.id
      end
    end

    test "draft scope returns draft invoices" do
      draft = mollie_pay_sales_invoices(:acme_draft)
      issued = mollie_pay_sales_invoices(:acme_issued)

      assert_includes SalesInvoice.draft, draft
      assert_not_includes SalesInvoice.draft, issued
    end

    test "issued scope returns issued invoices" do
      issued = mollie_pay_sales_invoices(:acme_issued)
      draft = mollie_pay_sales_invoices(:acme_draft)

      assert_includes SalesInvoice.issued, issued
      assert_not_includes SalesInvoice.issued, draft
    end

    test "paid scope returns paid invoices" do
      assert_empty SalesInvoice.paid
    end

    test "overdue scope returns issued invoices past due" do
      issued = mollie_pay_sales_invoices(:acme_issued)
      issued.update!(due_at: 1.day.ago)

      assert_includes SalesInvoice.overdue, issued
    end

    test "overdue scope excludes invoices not yet due" do
      issued = mollie_pay_sales_invoices(:acme_issued)
      issued.update!(due_at: 1.day.from_now)

      assert_not_includes SalesInvoice.overdue, issued
    end

    test "requires mollie_id" do
      invoice = SalesInvoice.new(status: "draft")
      assert_not invoice.valid?
      assert_includes invoice.errors[:mollie_id], "can't be blank"
    end

    test "requires unique mollie_id" do
      existing = mollie_pay_sales_invoices(:acme_draft)
      invoice = SalesInvoice.new(
        mollie_id: existing.mollie_id,
        status: "draft",
        customer: existing.customer
      )
      assert_not invoice.valid?
      assert_includes invoice.errors[:mollie_id], "has already been taken"
    end

    test "requires valid status" do
      invoice = mollie_pay_sales_invoices(:acme_draft)
      invoice.status = "nonsense"
      assert_not invoice.valid?
    end

    test "requires positive amount when present" do
      invoice = mollie_pay_sales_invoices(:acme_issued)
      invoice.amount = 0
      assert_not invoice.valid?

      invoice.amount = -1
      assert_not invoice.valid?
    end

    test "allows nil amount for drafts" do
      invoice = mollie_pay_sales_invoices(:acme_draft)
      invoice.amount = nil
      invoice.currency = nil
      assert invoice.valid?
    end

    test "status predicates" do
      draft = mollie_pay_sales_invoices(:acme_draft)
      assert draft.draft?
      assert_not draft.issued?
      assert_not draft.paid?
      assert_not draft.canceled?

      issued = mollie_pay_sales_invoices(:acme_issued)
      assert issued.issued?
      assert_not issued.draft?
    end

    test "amount_decimal returns amount in decimal" do
      invoice = mollie_pay_sales_invoices(:acme_issued)
      assert_in_delta 107.69, invoice.amount_decimal, 0.001
    end

    test "mollie_amount returns formatted hash" do
      invoice = mollie_pay_sales_invoices(:acme_issued)
      expected = { currency: "EUR", value: "107.69" }
      assert_equal expected, invoice.mollie_amount
    end

    private

    def fake_mollie_si(id:, status:, invoice_number: nil, recipient_identifier: nil,
                       memo: nil, amount_value: nil, amount_currency: nil,
                       issued_at: nil, paid_at: nil, due_at: nil)
      total_amount = if amount_value
        OpenStruct.new(value: amount_value, currency: amount_currency)
      end

      OpenStruct.new(
        id: id,
        status: status,
        invoice_number: invoice_number,
        recipient_identifier: recipient_identifier,
        memo: memo,
        total_amount: total_amount,
        issued_at: issued_at,
        paid_at: paid_at,
        due_at: due_at
      )
    end
  end
end
