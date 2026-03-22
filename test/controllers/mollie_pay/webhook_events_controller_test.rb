require "test_helper"

module MolliePay
  class WebhookEventsControllerTest < ActionDispatch::IntegrationTest
    setup do
      MolliePay.configuration.webhook_signing_secret = WEBHOOK_TEST_SECRET
    end

    teardown do
      MolliePay.configuration.webhook_signing_secret = nil
    end

    test "accepts validly signed event and enqueues job" do
      assert_enqueued_with(job: ProcessWebhookEventJob) do
        post_signed_webhook_event(event_type: "sales-invoice.paid", entity_id: "invoice_test123")
      end

      assert_response :ok
    end

    test "rejects invalid signature" do
      payload = { resource: "event", id: "whe_test1", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json
      signature = "sha256=0000000000000000000000000000000000000000000000000000000000000000"

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }

      assert_response :bad_request
    end

    test "rejects malformed signature format" do
      payload = { resource: "event", id: "whe_test1", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => "md5=abc123" }

      assert_response :bad_request
    end

    test "rejects missing signature when secret is configured" do
      payload = { resource: "event", id: "whe_test1", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json" }

      assert_response :bad_request
    end

    test "accepts event without signature when no secret configured" do
      MolliePay.configuration.webhook_signing_secret = nil

      payload = { resource: "event", id: "whe_test1", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json

      assert_enqueued_with(job: ProcessWebhookEventJob) do
        post mollie_pay.webhook_events_path,
          params: payload,
          headers: { "CONTENT_TYPE" => "application/json" }
      end

      assert_response :ok
    end

    test "accepts event with valid signature when no secret configured" do
      MolliePay.configuration.webhook_signing_secret = nil

      post_signed_webhook_event(event_type: "sales-invoice.paid", entity_id: "invoice_1")

      assert_response :ok
    end

    test "rejects empty body" do
      post mollie_pay.webhook_events_path,
        params: "",
        headers: { "CONTENT_TYPE" => "application/json" }

      assert_response :bad_request
    end

    test "rejects malformed JSON" do
      raw = "not json at all"
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', WEBHOOK_TEST_SECRET, raw)}"

      post mollie_pay.webhook_events_path,
        params: raw,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }

      assert_response :bad_request
    end

    test "rejects JSON missing required id field" do
      payload = { resource: "event", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', WEBHOOK_TEST_SECRET, payload)}"

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }

      assert_response :unprocessable_entity
    end

    test "rejects JSON missing required type field" do
      payload = { resource: "event", id: "whe_test1", entityId: "invoice_1" }.to_json
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', WEBHOOK_TEST_SECRET, payload)}"

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }

      assert_response :unprocessable_entity
    end

    test "accepts unknown event types" do
      assert_enqueued_with(job: ProcessWebhookEventJob) do
        post_signed_webhook_event(event_type: "future.unknown-event", entity_id: "entity_1")
      end

      assert_response :ok
    end

    test "secret rotation: accepts when second secret matches" do
      MolliePay.configuration.webhook_signing_secret = [ "new_secret_abc", "old_secret_xyz" ]

      payload = { resource: "event", id: "whe_rot1", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'old_secret_xyz', payload)}"

      assert_enqueued_with(job: ProcessWebhookEventJob) do
        post mollie_pay.webhook_events_path,
          params: payload,
          headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }
      end

      assert_response :ok
    end

    test "secret rotation: rejects when no secret matches" do
      MolliePay.configuration.webhook_signing_secret = [ "secret_a", "secret_b" ]

      payload = { resource: "event", id: "whe_rot2", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json
      signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'secret_c_wrong', payload)}"

      post mollie_pay.webhook_events_path,
        params: payload,
        headers: { "CONTENT_TYPE" => "application/json", "HTTP_X_MOLLIE_SIGNATURE" => signature }

      assert_response :bad_request
    end

    test "empty array signing secret is treated as not configured" do
      MolliePay.configuration.webhook_signing_secret = []

      payload = { resource: "event", id: "whe_empty", type: "sales-invoice.paid", entityId: "invoice_1" }.to_json

      assert_enqueued_with(job: ProcessWebhookEventJob) do
        post mollie_pay.webhook_events_path,
          params: payload,
          headers: { "CONTENT_TYPE" => "application/json" }
      end

      assert_response :ok
    end
  end
end
