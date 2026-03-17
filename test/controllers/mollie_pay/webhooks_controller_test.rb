require "test_helper"

module MolliePay
  class WebhooksControllerTest < ActionDispatch::IntegrationTest
    test "creates webhook event and responds 200" do
      assert_difference "MolliePay::WebhookEvent.count", 1 do
        post mollie_pay.webhooks_url, params: { id: "tr_new456" }
      end

      assert_response :ok
    end

    test "enqueues processing job" do
      assert_enqueued_with(job: MolliePay::ProcessWebhookJob) do
        post mollie_pay.webhooks_url, params: { id: "tr_new456" }
      end
    end

    test "deduplicates already-received webhook events" do
      post mollie_pay.webhooks_url, params: { id: "tr_dedup789" }
      assert_response :ok

      assert_no_difference "MolliePay::WebhookEvent.count" do
        post mollie_pay.webhooks_url, params: { id: "tr_dedup789" }
      end

      assert_response :ok
    end

    test "deduplicates already-processed webhook events" do
      event = MolliePay::WebhookEvent.create!(mollie_id: "tr_processed123")
      event.update!(processed_at: Time.current)

      assert_no_difference "MolliePay::WebhookEvent.count" do
        post mollie_pay.webhooks_url, params: { id: "tr_processed123" }
      end

      assert_response :ok
    end

    test "returns 422 without id param" do
      assert_no_difference "MolliePay::WebhookEvent.count" do
        post mollie_pay.webhooks_url, params: {}
      end

      assert_response :unprocessable_entity
    end

    test "returns 422 with invalid mollie_id format" do
      assert_no_difference "MolliePay::WebhookEvent.count" do
        post mollie_pay.webhooks_url, params: { id: "invalid_format" }
      end

      assert_response :unprocessable_entity
    end
  end
end
