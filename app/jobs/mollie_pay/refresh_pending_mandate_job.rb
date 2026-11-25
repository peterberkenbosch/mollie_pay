module MolliePay
  # Mollie sends no webhook for a mandate, and none for a first payment once it
  # is paid. A mandate that was still pending at that moment is re-fetched here
  # until Mollie reports it valid or invalid. Mandate.record_from_mollie_mandate
  # fires on_mollie_mandate_created on the transition to valid.
  class RefreshPendingMandateJob < ApplicationJob
    queue_as :default

    retry_on StandardError,  wait: :polynomially_longer, attempts: 5
    retry_on MandatePending, wait: :polynomially_longer, attempts: 10
    discard_on ActiveJob::DeserializationError
    discard_on Mollie::ResourceNotFoundError

    def perform(mandate)
      refreshed = Mandate.record_from_mollie_mandate(mandate.mollie_record, mandate.customer)

      if refreshed.pending?
        raise MandatePending, "Mandate #{refreshed.mollie_id} is still pending"
      end
    end
  end
end
