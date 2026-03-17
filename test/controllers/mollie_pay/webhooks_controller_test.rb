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

    test "creates separate events for same mollie_id" do
      post mollie_pay.webhooks_url, params: { id: "tr_multi789" }
      assert_response :ok

      assert_difference "MolliePay::WebhookEvent.count", 1 do
        post mollie_pay.webhooks_url, params: { id: "tr_multi789" }
      end

      assert_response :ok
    end

    test "creates event even if prior event for same mollie_id was processed" do
      event = MolliePay::WebhookEvent.create!(mollie_id: "tr_processed123")
      event.update!(processed_at: Time.current)

      assert_difference "MolliePay::WebhookEvent.count", 1 do
        post mollie_pay.webhooks_url, params: { id: "tr_processed123" }
      end

      assert_response :ok
    end

    test "enqueues a job for each webhook event" do
      assert_enqueued_jobs 2, only: MolliePay::ProcessWebhookJob do
        post mollie_pay.webhooks_url, params: { id: "tr_jobs123" }
        post mollie_pay.webhooks_url, params: { id: "tr_jobs123" }
      end
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
