require "test_helper"

module MolliePay
  class ProcessWebhookJobTest < ActiveJob::TestCase
    test "calls process! on the event" do
      event = mollie_pay_webhook_events(:pending_event)
      called = false

      mock_event = Object.new
      mock_event.define_singleton_method(:processed?) { false }
      mock_event.define_singleton_method(:process!) { called = true }

      WebhookEvent.stub(:find, mock_event) do
        ProcessWebhookJob.perform_now(event.id)
      end

      assert called
    end

    test "retries on failure" do
      event = mollie_pay_webhook_events(:pending_event)
      mock_event = Object.new
      mock_event.define_singleton_method(:processed?) { false }
      mock_event.define_singleton_method(:process!) { raise StandardError, "Mollie down" }

      WebhookEvent.stub(:find, mock_event) do
        assert_enqueued_with(job: ProcessWebhookJob) do
          ProcessWebhookJob.perform_now(event.id)
        end
      end
    end

    test "discards when record not found" do
      event = mollie_pay_webhook_events(:pending_event)
      mock_event = Object.new
      mock_event.define_singleton_method(:processed?) { false }
      mock_event.define_singleton_method(:process!) { raise ActiveRecord::RecordNotFound }

      WebhookEvent.stub(:find, mock_event) do
        assert_no_enqueued_jobs only: ProcessWebhookJob do
          ProcessWebhookJob.perform_now(event.id)
        end
      end
    end

    test "skips already processed events" do
      event = mollie_pay_webhook_events(:payment_event)
      assert event.processed?

      mock_event = Object.new
      mock_event.define_singleton_method(:processed?) { true }
      process_called = false
      mock_event.define_singleton_method(:process!) { process_called = true }

      WebhookEvent.stub(:find, mock_event) do
        ProcessWebhookJob.perform_now(event.id)
      end

      assert_not process_called
    end
  end
end
