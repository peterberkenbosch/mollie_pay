require "test_helper"

class MolliePay::SalesInvoicesTest < ActiveSupport::TestCase
  test "create_sales_invoice passes correct params to SDK" do
    received_data = nil
    received_options = nil
    fake_create = ->(data, options) { received_data = data; received_options = options; fake_invoice }

    Mollie::SalesInvoice.stub(:create, fake_create) do
      MolliePay.create_sales_invoice(
        status: "issued",
        recipient: { type: "consumer", given_name: "Jane", family_name: "Doe", email: "jane@example.com" },
        lines: [ { description: "Pro plan", quantity: 1, vat_rate: "21.00", unit_price: 8900 } ],
        email_details: { subject: "Your invoice", body: "Please pay" }
      )
    end

    assert_equal "issued", received_data[:status]
    assert_equal({ type: "consumer", givenName: "Jane", familyName: "Doe", email: "jane@example.com" }, received_data[:recipient])
    assert_equal "Pro plan", received_data[:lines].first[:description]
    assert_equal({ subject: "Your invoice", body: "Please pay" }, received_data[:emailDetails])
    assert received_options[:idempotency_key].present?
  end

  test "create_sales_invoice converts line item unit_price from cents" do
    received_data = nil
    fake_create = ->(data, _options) { received_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:create, fake_create) do
      MolliePay.create_sales_invoice(
        status: "draft",
        recipient: { type: "consumer", given_name: "Jane" },
        lines: [ { description: "Item", quantity: 1, vat_rate: "21.00", unit_price: 8900 } ]
      )
    end

    line = received_data[:lines].first
    assert_equal({ currency: "EUR", value: "89.00" }, line[:unitPrice])
  end

  test "create_sales_invoice passes hash unit_price as-is" do
    received_data = nil
    fake_create = ->(data, _options) { received_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:create, fake_create) do
      MolliePay.create_sales_invoice(
        status: "draft",
        recipient: { type: "consumer", given_name: "Jane" },
        lines: [ { description: "Item", quantity: 1, vat_rate: "21.00", unit_price: { currency: "EUR", value: "89.00" } } ]
      )
    end

    line = received_data[:lines].first
    assert_equal({ currency: "EUR", value: "89.00" }, line[:unitPrice])
  end

  test "create_sales_invoice camelizes recipient keys" do
    received_data = nil
    fake_create = ->(data, _options) { received_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:create, fake_create) do
      MolliePay.create_sales_invoice(
        status: "draft",
        recipient: {
          type: "business",
          organization_name: "Acme B.V.",
          vat_number: "NL123456789B01",
          street_and_number: "Keizersgracht 126",
          postal_code: "1015 CX",
          city: "Amsterdam",
          country: "NL"
        },
        lines: [ { description: "Item", quantity: 1, vat_rate: "21.00", unit_price: 1000 } ]
      )
    end

    recipient = received_data[:recipient]
    assert_equal "business", recipient[:type]
    assert_equal "Acme B.V.", recipient[:organizationName]
    assert_equal "NL123456789B01", recipient[:vatNumber]
    assert_equal "Keizersgracht 126", recipient[:streetAndNumber]
    assert_equal "1015 CX", recipient[:postalCode]
  end

  test "create_sales_invoice forwards payment_details and payment_term" do
    received_data = nil
    fake_create = ->(data, _options) { received_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:create, fake_create) do
      MolliePay.create_sales_invoice(
        status: "paid",
        recipient: { type: "consumer", given_name: "Jane" },
        lines: [ { description: "Item", quantity: 1, vat_rate: "21.00", unit_price: 1000 } ],
        payment_term: "30 days",
        payment_details: { source: "manual" }
      )
    end

    assert_equal "30 days", received_data[:paymentTerm]
    assert_equal({ source: "manual" }, received_data[:paymentDetails])
  end

  test "sales_invoice delegates to Mollie::SalesInvoice.get" do
    called_with_id = nil
    fake_get = ->(id) { called_with_id = id; fake_invoice }

    Mollie::SalesInvoice.stub(:get, fake_get) do
      MolliePay.sales_invoice("invoice_abc123")
    end

    assert_equal "invoice_abc123", called_with_id
  end

  test "sales_invoices delegates to Mollie::SalesInvoice.all" do
    called_with = nil
    fake_all = ->(options) { called_with = options; [] }

    Mollie::SalesInvoice.stub(:all, fake_all) do
      MolliePay.sales_invoices(limit: 10)
    end

    assert_equal({ limit: 10 }, called_with)
  end

  test "update_sales_invoice delegates to Mollie::SalesInvoice.update" do
    called_with_id = nil
    called_with_data = nil
    fake_update = ->(id, data) { called_with_id = id; called_with_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:update, fake_update) do
      MolliePay.update_sales_invoice("invoice_abc123", memo: "Updated", payment_term: "14 days")
    end

    assert_equal "invoice_abc123", called_with_id
    assert_equal "Updated", called_with_data[:memo]
    assert_equal "14 days", called_with_data[:paymentTerm]
  end

  test "update_sales_invoice camelizes nested recipient" do
    called_with_data = nil
    fake_update = ->(_id, data) { called_with_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:update, fake_update) do
      MolliePay.update_sales_invoice("invoice_abc123",
        recipient: { given_name: "Updated Jane" }
      )
    end

    assert_equal "Updated Jane", called_with_data[:recipient][:givenName]
  end

  test "update_sales_invoice converts line item unit_price" do
    called_with_data = nil
    fake_update = ->(_id, data) { called_with_data = data; fake_invoice }

    Mollie::SalesInvoice.stub(:update, fake_update) do
      MolliePay.update_sales_invoice("invoice_abc123",
        lines: [ { description: "New item", quantity: 2, vat_rate: "21.00", unit_price: 5000 } ]
      )
    end

    line = called_with_data[:lines].first
    assert_equal({ currency: "EUR", value: "50.00" }, line[:unitPrice])
  end

  test "delete_sales_invoice delegates to Mollie::SalesInvoice.delete" do
    called_with_id = nil
    fake_delete = ->(id) { called_with_id = id; nil }

    Mollie::SalesInvoice.stub(:delete, fake_delete) do
      MolliePay.delete_sales_invoice("invoice_abc123")
    end

    assert_equal "invoice_abc123", called_with_id
  end

  private

    def fake_invoice
      OpenStruct.new(id: "invoice_abc123", status: "draft")
    end
end
