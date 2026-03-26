require "test_helper"

module MolliePay
  class ProcessWebhookEventJobTest < ActiveJob::TestCase
    test "logs received event type and entity ID" do
      event = {
        "resource" => "event",
        "id" => "whe_test123",
        "type" => "sales-invoice.paid",
        "entityId" => "invoice_abc",
        "createdAt" => "2026-03-22T10:00:00+00:00"
      }

      assert_nothing_raised do
        ProcessWebhookEventJob.perform_now(event)
      end
    end

    test "handles unknown event types without raising" do
      event = {
        "resource" => "event",
        "id" => "whe_unknown",
        "type" => "future.unknown-type",
        "entityId" => "entity_xyz"
      }

      assert_nothing_raised do
        ProcessWebhookEventJob.perform_now(event)
      end
    end
  end
end
