require "json"

module MolliePay
  module TestHelper
    MOLLIE_API_BASE = "https://api.mollie.com/v2".freeze
    FIXTURES_PATH   = File.expand_path("test_fixtures", __dir__).freeze

    # ── Method-level stubs ─────────────────────────────────────────────
    #
    # Fast, simple stubs that bypass HTTP entirely. Use these for unit
    # tests where you just need MolliePay methods to return a record.

    # Stub Mollie::Payment.create and yield.
    #
    #   stub_mollie_payment_create do
    #     payment = @user.mollie_pay_once(amount: 5000, description: "Test")
    #     assert_equal "open", payment.status
    #     assert payment.checkout_url.present?
    #   end
    #
    # With method and metadata:
    #
    #   stub_mollie_payment_create do
    #     payment = @user.mollie_pay_first(
    #       amount: 1000, description: "Setup",
    #       redirect_url: billing_url,
    #       method: "ideal",
    #       metadata: { plan: "yearly" }
    #     )
    #   end
    #
    def stub_mollie_payment_create(**overrides, &block)
      response = fake_mollie_payment(**overrides)
      Mollie::Payment.stub(:create, response, &block)
    end

    # Stub Mollie::Customer.create and Mollie::Payment.create together.
    # Use this when testing a billable that has no Mollie customer yet.
    #
    #   stub_mollie_customer_and_payment_create do
    #     payment = new_user.mollie_pay_once(amount: 1000, description: "First")
    #     assert new_user.reload.mollie_customer.present?
    #   end
    #
    def stub_mollie_customer_and_payment_create(customer_overrides: {}, payment_overrides: {}, &block)
      customer_response = fake_mollie_customer(**customer_overrides)
      payment_response  = fake_mollie_payment(**payment_overrides)

      Mollie::Customer.stub(:create, customer_response) do
        Mollie::Payment.stub(:create, payment_response, &block)
      end
    end

    # Stub Mollie::Customer::Subscription.create.
    #
    # Note: mollie_subscribe has an idempotency guard — it returns an existing
    # pending/active subscription without hitting the Mollie API. Cancel or
    # remove existing subscriptions in your test setup if you need to test
    # subscription creation.
    #
    #   stub_mollie_subscription_create do
    #     subscription = @user.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")
    #     assert_equal "active", subscription.status
    #   end
    #
    # With start_date (for credit card first payments):
    #
    #   stub_mollie_subscription_create do
    #     subscription = @user.mollie_subscribe(
    #       amount: 2500, interval: "1 month",
    #       description: "Monthly", start_date: Date.today + 1.month
    #     )
    #   end
    #
    def stub_mollie_subscription_create(**overrides, &block)
      response = fake_mollie_subscription(**overrides)
      Mollie::Customer::Subscription.stub(:create, response, &block)
    end

    # Stub Mollie::Customer::Subscription.cancel.
    #
    #   stub_mollie_subscription_cancel do
    #     @user.mollie_cancel_subscription
    #   end
    #
    def stub_mollie_subscription_cancel(&block)
      Mollie::Customer::Subscription.stub(:cancel, nil, &block)
    end

    # Stub Mollie::Customer::Subscription.update.
    #
    #   stub_mollie_subscription_update do
    #     @user.mollie_swap_subscription(amount: 4999)
    #   end
    #
    def stub_mollie_subscription_update(**overrides, &block)
      response = fake_mollie_subscription(**overrides)
      Mollie::Customer::Subscription.stub(:update, response, &block)
    end

    # Stub Mollie::Customer.update.
    #
    #   stub_mollie_customer_update do
    #     @org.mollie_update_customer(name: "New Name")
    #   end
    #
    def stub_mollie_customer_update(&block)
      Mollie::Customer.stub(:update, OpenStruct.new, &block)
    end

    # Stub Mollie::Customer.delete.
    #
    #   stub_mollie_customer_delete do
    #     @org.mollie_delete_customer
    #   end
    #
    def stub_mollie_customer_delete(&block)
      Mollie::Customer.stub(:delete, nil, &block)
    end

    # Stub Mollie::Customer::Mandate.create.
    #
    #   stub_mollie_mandate_create do
    #     mandate = @user.mollie_create_mandate(
    #       method: "directdebit", consumer_name: "John Doe",
    #       consumer_account: "NL55INGB0000000000"
    #     )
    #     assert_equal "valid", mandate.status
    #   end
    #
    def stub_mollie_mandate_create(**overrides, &block)
      response = fake_mollie_mandate(**overrides)
      Mollie::Customer::Mandate.stub(:create, response, &block)
    end

    # Stub Mollie::Customer::Mandate.delete.
    #
    #   stub_mollie_mandate_revoke do
    #     @user.mollie_revoke_mandate(mandate)
    #   end
    #
    def stub_mollie_mandate_revoke(&block)
      Mollie::Customer::Mandate.stub(:delete, nil, &block)
    end

    # Stub Mollie::Refund.create.
    #
    #   stub_mollie_refund_create do
    #     refund = @user.mollie_refund(payment)
    #     assert_equal "queued", refund.status
    #   end
    #
    def stub_mollie_refund_create(**overrides, &block)
      response = fake_mollie_refund(**overrides)
      Mollie::Refund.stub(:create, response, &block)
    end

    # ── Next-Gen Webhook Event helpers ──────────────────────────────
    #
    # Post a signed next-gen webhook event to the engine's webhook_events
    # endpoint. Generates a valid HMAC-SHA256 signature using the provided
    # secret (or the test default).
    #
    #   MolliePay.configuration.webhook_signing_secret = WEBHOOK_TEST_SECRET
    #   post_signed_webhook_event(event_type: "sales-invoice.paid", entity_id: "invoice_xxx")
    #   assert_response :ok
    #
    # Pass `secret: nil` to omit the signature header (for testing unsigned events).
    #
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

    # Build a fake Mollie payment response (OpenStruct).
    def fake_mollie_payment(id: nil, status: "open", checkout_url: nil)
      id           ||= "tr_test#{SecureRandom.hex(4)}"
      checkout_url ||= "https://www.mollie.com/payscreen/select-method/#{id}"

      OpenStruct.new(id: id, status: status, checkout_url: checkout_url)
    end

    # Build a fake Mollie customer response (OpenStruct).
    def fake_mollie_customer(id: nil)
      id ||= "cst_test#{SecureRandom.hex(4)}"
      OpenStruct.new(id: id)
    end

    # Build a fake Mollie mandate response (OpenStruct).
    def fake_mollie_mandate(id: nil, status: "valid", method: "directdebit")
      id ||= "mdt_test#{SecureRandom.hex(4)}"
      OpenStruct.new(id: id, status: status, method: method)
    end

    # Build a fake Mollie subscription response (OpenStruct).
    def fake_mollie_subscription(id: nil, status: "active")
      id ||= "sub_test#{SecureRandom.hex(4)}"
      OpenStruct.new(id: id, status: status)
    end

    # Build a fake Mollie refund response (OpenStruct).
    def fake_mollie_refund(id: nil, status: "queued")
      id ||= "re_test#{SecureRandom.hex(4)}"
      OpenStruct.new(id: id, status: status)
    end

    # Build a fake Mollie sales invoice response (OpenStruct).
    # Simple version for stub helpers.
    def fake_mollie_sales_invoice(id: nil, status: "draft")
      id ||= "invoice_test#{SecureRandom.hex(4)}"
      OpenStruct.new(
        id: id,
        status: status,
        invoice_number: nil,
        recipient_identifier: nil
      )
    end

    # Build a fake Mollie sales invoice response with all fields needed
    # for SalesInvoice.record_from_mollie. Use this when testing Billable
    # methods that persist local records.
    def fake_mollie_sales_invoice_response(id: nil, status: "draft")
      id ||= "invoice_test#{SecureRandom.hex(4)}"
      OpenStruct.new(
        id: id,
        status: status,
        invoice_number: status == "issued" ? "INV-0000001" : nil,
        total_amount: OpenStruct.new(value: BigDecimal("107.69"), currency: "EUR"),
        recipient_identifier: "cust-test",
        memo: "Test invoice",
        issued_at: status == "issued" ? Time.current : nil,
        paid_at: status == "paid" ? Time.current : nil,
        due_at: 30.days.from_now
      )
    end

    # Stub Mollie::SalesInvoice.create.
    #
    #   stub_mollie_sales_invoice_create do
    #     invoice = MolliePay.create_sales_invoice(
    #       status: "draft",
    #       recipient: { type: "consumer", given_name: "Jane" },
    #       lines: [{ description: "Item", quantity: 1, vat_rate: "21.00", unit_price: 1000 }]
    #     )
    #     assert_equal "draft", invoice.status
    #   end
    #
    def stub_mollie_sales_invoice_create(**overrides, &block)
      response = fake_mollie_sales_invoice(**overrides)
      Mollie::SalesInvoice.stub(:create, response, &block)
    end

    # Stub Mollie::SalesInvoice.get.
    #
    #   stub_mollie_sales_invoice_get do
    #     invoice = MolliePay.sales_invoice("invoice_abc123")
    #     assert_equal "issued", invoice.status
    #   end
    #
    def stub_mollie_sales_invoice_get(**overrides, &block)
      response = fake_mollie_sales_invoice(**overrides)
      Mollie::SalesInvoice.stub(:get, response, &block)
    end

    # ── WebMock-based API stubs ────────────────────────────────────────
    #
    # These stub the actual HTTP endpoints that the Mollie SDK calls.
    # The full SDK parsing pipeline runs — JSON is deserialized into real
    # Mollie::Payment, Mollie::Customer, etc. objects. Use these for
    # integration tests or when you want higher-fidelity stubbing.
    #
    # Requires `require "webmock/minitest"` in your test_helper.rb.

    # Stub POST /v2/payments to return a realistic Mollie API response.
    # The Mollie SDK parses the JSON into a real Mollie::Payment object.
    #
    #   webmock_mollie_payment_create do
    #     payment = @user.mollie_pay_once(amount: 5000, description: "Test")
    #     assert_equal "open", payment.status
    #     assert_equal "https://www.mollie.com/payscreen/select-method/test1234AB", payment.checkout_url
    #   end
    #
    # Pass overrides to merge into the JSON response:
    #
    #   webmock_mollie_payment_create(id: "tr_custom", status: "paid") do
    #     ...
    #   end
    #
    def webmock_mollie_payment_create(**overrides)
      body = mollie_fixture("payment", **overrides)
      stub_request(:post, "#{MOLLIE_API_BASE}/payments")
        .to_return(status: 201, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub POST /v2/customers and POST /v2/payments together.
    #
    #   webmock_mollie_customer_and_payment_create do
    #     payment = new_user.mollie_pay_once(amount: 1000, description: "First")
    #     assert new_user.reload.mollie_customer.present?
    #   end
    #
    def webmock_mollie_customer_and_payment_create(customer_overrides: {}, payment_overrides: {})
      customer_body = mollie_fixture("customer", **customer_overrides)
      payment_body  = mollie_fixture("payment", **payment_overrides)

      stub_request(:post, "#{MOLLIE_API_BASE}/customers")
        .to_return(status: 201, body: customer_body, headers: { "Content-Type" => "application/hal+json" })
      stub_request(:post, "#{MOLLIE_API_BASE}/payments")
        .to_return(status: 201, body: payment_body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub POST /v2/customers/:customer_id/subscriptions.
    #
    #   webmock_mollie_subscription_create(customer_id: "cst_abc") do
    #     subscription = @user.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")
    #     assert_equal "active", subscription.status
    #   end
    #
    def webmock_mollie_subscription_create(customer_id: nil, **overrides)
      body = mollie_fixture("subscription", **overrides)
      url_pattern = if customer_id
        "#{MOLLIE_API_BASE}/customers/#{customer_id}/subscriptions"
      else
        %r{#{MOLLIE_API_BASE}/customers/cst_\w+/subscriptions}
      end
      stub_request(:post, url_pattern)
        .to_return(status: 201, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub DELETE /v2/customers/:customer_id/subscriptions/:id.
    #
    #   webmock_mollie_subscription_cancel(customer_id: "cst_abc", subscription_id: "sub_xyz") do
    #     @user.mollie_cancel_subscription
    #   end
    #
    def webmock_mollie_subscription_cancel(customer_id: nil, subscription_id: "sub_test1234AB")
      url_pattern = if customer_id
        "#{MOLLIE_API_BASE}/customers/#{customer_id}/subscriptions/#{subscription_id}"
      else
        %r{#{MOLLIE_API_BASE}/customers/cst_\w+/subscriptions/#{subscription_id}}
      end
      stub_request(:delete, url_pattern)
        .to_return(status: 204, body: "", headers: {})
      yield
    ensure
      WebMock.reset!
    end

    # Stub POST /v2/refunds.
    # The Mollie SDK sends paymentId in the request body, not the URL.
    #
    #   webmock_mollie_refund_create do
    #     refund = @user.mollie_refund(payment)
    #     assert_equal "queued", refund.status
    #   end
    #
    def webmock_mollie_refund_create(**overrides)
      body = mollie_fixture("refund", **overrides)
      stub_request(:post, "#{MOLLIE_API_BASE}/refunds")
        .to_return(status: 201, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub GET /v2/payments/:id for webhook processing tests.
    #
    #   webmock_mollie_payment_get("tr_abc123", status: "paid") do
    #     MolliePay::ProcessWebhookJob.perform_now(event.id)
    #   end
    #
    def webmock_mollie_payment_get(payment_id, **overrides)
      body = mollie_fixture("payment", id: payment_id, **overrides)
      stub_request(:get, "#{MOLLIE_API_BASE}/payments/#{payment_id}")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub POST /v2/sales-invoices.
    #
    #   webmock_mollie_sales_invoice_create do
    #     invoice = MolliePay.create_sales_invoice(...)
    #   end
    #
    def webmock_mollie_sales_invoice_create(**overrides)
      body = mollie_fixture("sales_invoice", **overrides)
      stub_request(:post, "#{MOLLIE_API_BASE}/sales-invoices")
        .to_return(status: 201, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub GET /v2/sales-invoices/:id.
    #
    #   webmock_mollie_sales_invoice_get("invoice_abc123") do
    #     invoice = MolliePay.sales_invoice("invoice_abc123")
    #   end
    #
    def webmock_mollie_sales_invoice_get(invoice_id, **overrides)
      body = mollie_fixture("sales_invoice", id: invoice_id, **overrides)
      stub_request(:get, "#{MOLLIE_API_BASE}/sales-invoices/#{invoice_id}")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    # Stub GET /v2/payments/:id with embedded chargebacks for chargeback
    # detection tests. Uses the payment_with_chargebacks fixture which
    # includes _embedded.chargebacks matching the Mollie API structure.
    #
    #   webmock_mollie_payment_get_with_chargebacks("tr_abc123") do
    #     MolliePay::ProcessWebhookJob.perform_now("tr_abc123")
    #   end
    #
    def webmock_mollie_payment_get_with_chargebacks(payment_id, **overrides)
      body = mollie_fixture("payment_with_chargebacks", id: payment_id, **overrides)
      stub_request(:get, "#{MOLLIE_API_BASE}/payments/#{payment_id}")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/hal+json" })
      yield
    ensure
      WebMock.reset!
    end

    private

    # Load a JSON fixture file and merge in overrides.
    # Top-level keys are replaced directly. Nested "amount" is handled
    # specially so you can pass `amount_value: "50.00"`.
    def mollie_fixture(name, **overrides)
      json = JSON.parse(File.read(File.join(FIXTURES_PATH, "#{name}.json")))

      # Handle amount shorthand: amount_value and amount_currency
      if overrides.key?(:amount_value) || overrides.key?(:amount_currency)
        json["amount"] ||= {}
        json["amount"]["value"]    = overrides.delete(:amount_value)    if overrides.key?(:amount_value)
        json["amount"]["currency"] = overrides.delete(:amount_currency) if overrides.key?(:amount_currency)
      end

      # Handle checkout_url shorthand — update the _links.checkout.href
      if overrides.key?(:checkout_url)
        checkout_url = overrides.delete(:checkout_url)
        json["_links"] ||= {}
        json["_links"]["checkout"] = { "href" => checkout_url, "type" => "text/html" }
      end

      # Merge remaining overrides as camelCase keys (Mollie API format)
      overrides.each do |key, value|
        json[camelize(key.to_s)] = value
      end

      json.to_json
    end

    def camelize(snake_str)
      parts = snake_str.split("_")
      parts[0] + parts[1..].map(&:capitalize).join
    end
  end
end
