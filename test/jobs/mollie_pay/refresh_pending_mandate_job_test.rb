require "test_helper"

module MolliePay
  class RefreshPendingMandateJobTest < ActiveJob::TestCase
    setup do
      @customer = mollie_pay_customers(:acme)
      @mandate = Mandate.create!(customer: @customer, mollie_id: "mdt_refresh", status: "pending", method: "directdebit")
      @created = []
      created = @created
      Organization.define_method(:on_mollie_mandate_created) { |mandate| created << mandate.mollie_id }
    end

    teardown do
      Organization.remove_method(:on_mollie_mandate_created)
    end

    test "a mandate Mollie now reports valid is stored and announced once" do
      stub_mandate_get(status: "valid")

      assert_no_enqueued_jobs(only: RefreshPendingMandateJob) do
        perform_enqueued_jobs(only: NotifyBillableJob) { RefreshPendingMandateJob.perform_now(@mandate) }
      end

      @mandate.reload
      assert_equal "valid", @mandate.status
      assert_not_nil @mandate.mandated_at
      assert_equal [ "mdt_refresh" ], @created
    end

    test "a mandate still pending is fetched again later" do
      stub_mandate_get(status: "pending")

      assert_enqueued_with(job: RefreshPendingMandateJob, args: [ @mandate ]) do
        RefreshPendingMandateJob.perform_now(@mandate)
      end

      assert_equal "pending", @mandate.reload.status
      assert_empty @created
    end

    test "a mandate Mollie reports invalid is stored and not fetched again" do
      stub_mandate_get(status: "invalid")

      assert_no_enqueued_jobs(only: RefreshPendingMandateJob) do
        RefreshPendingMandateJob.perform_now(@mandate)
      end

      assert_equal "invalid", @mandate.reload.status
      assert_empty @created
    end

    private

      # Shape follows the Get mandate example in Mollie's OpenAPI spec.
      def stub_mandate_get(status:)
        stub_request(:get, "#{MOLLIE_API_BASE}/customers/#{@customer.mollie_id}/mandates/#{@mandate.mollie_id}")
          .to_return(status: 200, headers: { "Content-Type" => "application/hal+json" }, body: {
            resource:         "mandate",
            id:               @mandate.mollie_id,
            mode:             "test",
            status:           status,
            method:           "directdebit",
            details:          { consumerName: "John Doe", consumerAccount: "NL55INGB0000000000", consumerBic: "INGBNL2A" },
            mandateReference: nil,
            signatureDate:    "2026-11-24",
            customerId:       @customer.mollie_id,
            createdAt:        "2026-11-24T10:49:08+00:00"
          }.to_json)
      end
  end
end
