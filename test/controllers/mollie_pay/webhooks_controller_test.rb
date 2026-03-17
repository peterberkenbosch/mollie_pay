require "test_helper"

module MolliePay
  class WebhooksControllerTest < ActionDispatch::IntegrationTest
    test "enqueues processing job and responds 200" do
      assert_enqueued_with(job: MolliePay::ProcessWebhookJob, args: [ "tr_new456" ]) do
        post mollie_pay.webhooks_url, params: { id: "tr_new456" }
      end

      assert_response :ok
    end

    test "accepts subscription webhook" do
      assert_enqueued_with(job: MolliePay::ProcessWebhookJob, args: [ "sub_abc123" ]) do
        post mollie_pay.webhooks_url, params: { id: "sub_abc123" }
      end

      assert_response :ok
    end

    test "accepts refund webhook" do
      assert_enqueued_with(job: MolliePay::ProcessWebhookJob, args: [ "re_abc123" ]) do
        post mollie_pay.webhooks_url, params: { id: "re_abc123" }
      end

      assert_response :ok
    end

    test "returns 422 without id param" do
      assert_no_enqueued_jobs only: MolliePay::ProcessWebhookJob do
        post mollie_pay.webhooks_url, params: {}
      end

      assert_response :unprocessable_entity
    end

    test "returns 422 with invalid mollie_id format" do
      assert_no_enqueued_jobs only: MolliePay::ProcessWebhookJob do
        post mollie_pay.webhooks_url, params: { id: "invalid_format" }
      end

      assert_response :unprocessable_entity
    end
  end
end
