module MolliePay
  # Calls one on_mollie_* hook on the host's billable model. The record whose
  # status changed is saved before this job is enqueued, so when a hook
  # raises, this job retries the hook. The webhook job's own retry would find
  # no transition left and never call it again. Hooks therefore run at least
  # once and must be idempotent.
  class NotifyBillableJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def perform(billable, hook, record)
      billable.public_send(hook, record)
    end
  end
end
