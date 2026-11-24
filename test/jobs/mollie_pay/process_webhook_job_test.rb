require "test_helper"

module MolliePay
  class ProcessWebhookJobTest < ActiveJob::TestCase
    test "processes payment webhook" do
      customer = mollie_pay_customers(:acme)

      webmock_mollie_payment_get("tr_newpayment", status: "paid", customer_id: customer.mollie_id) do
        ProcessWebhookJob.perform_now("tr_newpayment")
      end

      assert MolliePay::Payment.find_by(mollie_id: "tr_newpayment")
    end

    # === Billink (manual capture) lifecycle ===

    test "billink webhook moves an open payment to authorized once and fires the hook once" do
      payment = mollie_pay_payments(:acme_oneoff)

      with_organization_hook(:on_mollie_payment_authorized) do |calls|
        2.times do
          deliver_billink_webhook(payment, status: "authorized")
        end

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "authorized", payment.status
      assert_not_nil payment.authorized_at
    end

    test "billink webhook keeps authorized_at unchanged on a repeated authorized webhook" do
      payment = mollie_pay_payments(:acme_oneoff)

      deliver_billink_webhook(payment, status: "authorized")
      first_authorized_at = payment.reload.authorized_at

      travel 1.hour do
        deliver_billink_webhook(payment, status: "authorized")
      end

      assert_equal first_authorized_at, payment.reload.authorized_at
    end

    test "billink webhook moves an authorized payment to paid after capture and fires the paid hook once" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_paid) do |calls|
        deliver_billink_webhook(payment, status: "paid")

        assert_equal 1, calls.size
        assert_equal payment, calls.first
      end

      payment.reload
      assert_equal "paid", payment.status
      assert_not_nil payment.paid_at
      assert_not_nil payment.authorized_at
    end

    test "billink webhook moves an authorized payment to canceled after release and fires the canceled hook" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_canceled) do |calls|
        deliver_billink_webhook(payment, status: "canceled")

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "canceled", payment.status
      assert_not_nil payment.canceled_at
    end

    test "billink webhook moves an authorized payment to expired and fires the expired hook" do
      payment = mollie_pay_payments(:acme_authorized)

      with_organization_hook(:on_mollie_payment_expired) do |calls|
        deliver_billink_webhook(payment, status: "expired")

        assert_equal 1, calls.size
      end

      payment.reload
      assert_equal "expired", payment.status
      assert_not_nil payment.expired_at
    end

    test "processes subscription webhook" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      response = OpenStruct.new(
        id: subscription.mollie_id, status: "canceled",
        customer_id: subscription.customer.mollie_id,
        amount: OpenStruct.new(value: "25.00", currency: "EUR"),
        interval: "1 month", metadata: nil
      )

      Mollie::Subscription.stub(:get, response) do
        ProcessWebhookJob.perform_now(subscription.mollie_id)
      end

      assert_equal "canceled", subscription.reload.status
    end

    test "processes refund webhook" do
      refund = mollie_pay_refunds(:acme_refund)
      response = OpenStruct.new(
        id: refund.mollie_id, status: "refunded",
        payment_id: refund.payment.mollie_id,
        amount: OpenStruct.new(value: "75.00", currency: "EUR")
      )

      Mollie::Refund.stub(:get, response) do
        ProcessWebhookJob.perform_now(refund.mollie_id)
      end

      assert_equal "refunded", refund.reload.status
    end

    test "processes a canceled refund webhook without raising" do
      refund = mollie_pay_refunds(:acme_refund)
      response = OpenStruct.new(
        id: refund.mollie_id, status: "canceled",
        payment_id: refund.payment.mollie_id,
        amount: OpenStruct.new(value: "75.00", currency: "EUR")
      )

      Mollie::Refund.stub(:get, response) do
        ProcessWebhookJob.perform_now(refund.mollie_id)
      end

      assert_equal "canceled", refund.reload.status
    end

    test "processes settlement webhook via ActiveSupport::Notifications" do
      settlement = OpenStruct.new(
        id: "stl_test123", status: "paidout",
        amount: OpenStruct.new(value: "100.00", currency: "EUR")
      )

      received = nil
      ActiveSupport::Notifications.subscribe("mollie_pay.settlement_received") do |*, payload|
        received = payload[:settlement]
      end

      Mollie::Settlement.stub(:get, settlement) do
        ProcessWebhookJob.perform_now("stl_test123")
      end

      assert_equal "stl_test123", received.id
      assert_equal "paidout", received.status
    ensure
      ActiveSupport::Notifications.unsubscribe("mollie_pay.settlement_received")
    end

    test "logs unknown webhook prefix" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("ord_unknown123")
      end
    end

    test "retries on failure" do
      Mollie::Payment.stub(:get, ->(_) { raise StandardError, "Mollie down" }) do
        assert_enqueued_with(job: ProcessWebhookJob) do
          ProcessWebhookJob.perform_now("tr_test123")
        end
      end
    end

    test "discards when Mollie resource not found" do
      Mollie::Payment.stub(:get, ->(_) { raise Mollie::ResourceNotFoundError.new({}) }) do
        assert_nothing_raised do
          ProcessWebhookJob.perform_now("tr_nonexistent")
        end
      end
    end

    test "discards when local subscription not found" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("sub_nonexistent")
      end
    end

    test "discards when local refund not found" do
      assert_nothing_raised do
        ProcessWebhookJob.perform_now("re_nonexistent")
      end
    end

    # Pay by Bank settles asynchronously: the first payment sits in "pending"
    # until the funds arrive, and only then does Mollie's directdebit mandate
    # become usable.
    test "pending paybybank first payment records no mandate and fires no hooks" do
      payment = create_paybybank_first_payment("tr_pbbpending")
      hooks = record_billable_hooks

      assert_no_difference -> { Mandate.count } do
        webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, status: "pending")) do
          ProcessWebhookJob.perform_now(payment.mollie_id)
        end
      end

      assert_equal "pending", payment.reload.status
      assert_nil payment.paid_at
      assert_empty hooks
    ensure
      restore_billable_hooks
    end

    test "paid paybybank first payment records directdebit mandate and fires hooks once" do
      payment = create_paybybank_first_payment("tr_pbbpaid")
      customer = payment.customer
      hooks = record_billable_hooks

      webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, status: "pending")) do
        ProcessWebhookJob.perform_now(payment.mollie_id)
      end

      # Mollie may deliver the paid webhook more than once.
      2.times do
        webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, status: "paid", mandate_id: "mdt_pbb123")) do
          stub_request(:get, "#{MOLLIE_API_BASE}/customers/#{customer.mollie_id}/mandates/mdt_pbb123")
            .to_return(status: 200, body: directdebit_mandate_json("mdt_pbb123", customer), headers: { "Content-Type" => "application/hal+json" })

          ProcessWebhookJob.perform_now(payment.mollie_id)
        end
      end

      mandate = Mandate.find_by!(mollie_id: "mdt_pbb123")
      assert_equal "paid", payment.reload.status
      assert_not_nil payment.paid_at
      assert_equal "directdebit", mandate.method
      assert_equal "valid", mandate.status
      assert_not_nil mandate.mandated_at
      assert_equal [ [ :mandate_created, "mdt_pbb123" ], [ :first_payment_paid, "tr_pbbpaid" ] ], hooks
      assert_no_enqueued_jobs only: RefreshPendingMandateJob
    ensure
      restore_billable_hooks
    end

    test "mandate still pending when first payment is paid becomes valid on a later webhook" do
      payment = create_paybybank_first_payment("tr_pbblate")
      customer = payment.customer
      hooks = record_billable_hooks

      # Mollie may deliver the paid webhook more than once while the mandate is pending.
      %w[ pending pending valid ].each do |mandate_status|
        webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, status: "paid", mandate_id: "mdt_pbblate")) do
          stub_request(:get, "#{MOLLIE_API_BASE}/customers/#{customer.mollie_id}/mandates/mdt_pbblate")
            .to_return(status: 200, body: directdebit_mandate_json("mdt_pbblate", customer, status: mandate_status), headers: { "Content-Type" => "application/hal+json" })

          ProcessWebhookJob.perform_now(payment.mollie_id)
        end

        assert_equal mandate_status, Mandate.find_by!(mollie_id: "mdt_pbblate").status
      end

      assert_not_nil Mandate.find_by!(mollie_id: "mdt_pbblate").mandated_at
      assert_equal [ [ :first_payment_paid, "tr_pbblate" ], [ :mandate_created, "mdt_pbblate" ] ], hooks
      assert_enqueued_jobs 1, only: RefreshPendingMandateJob
    ensure
      restore_billable_hooks
    end

    # iDEAL can report the first payment paid while the mandate is still
    # pending, and Mollie sends no later webhook for either of them.
    test "mandate pending when an ideal first payment is paid is re-fetched until it is valid" do
      payment = create_paybybank_first_payment("tr_idealpending")
      customer = payment.customer
      hooks = record_billable_hooks
      mandate_url = "#{MOLLIE_API_BASE}/customers/#{customer.mollie_id}/mandates/mdt_idealpending"

      webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, method: "ideal", status: "paid", mandate_id: "mdt_idealpending")) do
        stub_request(:get, mandate_url)
          .to_return(status: 200, body: directdebit_mandate_json("mdt_idealpending", customer, status: "pending"), headers: { "Content-Type" => "application/hal+json" })

        ProcessWebhookJob.perform_now(payment.mollie_id)
      end

      assert_equal "pending", Mandate.find_by!(mollie_id: "mdt_idealpending").status

      stub_request(:get, mandate_url)
        .to_return(status: 200, body: directdebit_mandate_json("mdt_idealpending", customer, status: "valid"), headers: { "Content-Type" => "application/hal+json" })
      perform_enqueued_jobs

      mandate = Mandate.find_by!(mollie_id: "mdt_idealpending")
      assert_equal "valid", mandate.status
      assert_not_nil mandate.mandated_at
      assert_equal [ [ :first_payment_paid, "tr_idealpending" ], [ :mandate_created, "mdt_idealpending" ] ], hooks
    ensure
      WebMock.reset!
      restore_billable_hooks
    end

    private

      def deliver_billink_webhook(payment, status:)
        webmock_mollie_payment_get(payment.mollie_id, fixture: "payment_billink", status: status, customer_id: payment.customer.mollie_id) do
          ProcessWebhookJob.perform_now(payment.mollie_id)
        end
      end

      # Payment.record_from_mollie reloads the owner, so a singleton method on
      # a test-local instance is never reached. Define the hook on the class
      # for the duration of the block and collect the payments it received.
      def with_organization_hook(hook_name)
        calls = []
        Organization.define_method(hook_name) { |payment| calls << payment }
        yield calls
      ensure
        Organization.remove_method(hook_name)
      end

      BILLABLE_HOOKS = %i[ on_mollie_first_payment_paid on_mollie_payment_paid on_mollie_mandate_created ].freeze

      def create_paybybank_first_payment(mollie_id)
        Payment.create!(
          customer:      mollie_pay_customers(:acme),
          mollie_id:     mollie_id,
          status:        "open",
          amount:        BigDecimal("10.00"),
          currency:      "EUR",
          sequence_type: "first"
        )
      end

      def paybybank_payment(payment, **overrides)
        { method: "paybybank", sequence_type: "first", customer_id: payment.customer.mollie_id, **overrides }
      end

      # Shape follows the Get mandate example in Mollie's OpenAPI spec.
      def directdebit_mandate_json(mollie_id, customer, status: "valid")
        {
          resource:         "mandate",
          id:               mollie_id,
          mode:             "test",
          status:           status,
          method:           "directdebit",
          details:          { consumerName: "John Doe", consumerAccount: "NL55INGB0000000000", consumerBic: "INGBNL2A" },
          mandateReference: nil,
          signatureDate:    "2026-10-05",
          customerId:       customer.mollie_id,
          createdAt:        "2026-10-05T10:49:08+00:00"
        }.to_json
      end

      # The job loads its own owner instance, so hooks are observed on the class.
      def record_billable_hooks
        calls = []
        Organization.define_method(:on_mollie_first_payment_paid) { |payment| calls << [ :first_payment_paid, payment.mollie_id ] }
        Organization.define_method(:on_mollie_payment_paid)       { |payment| calls << [ :payment_paid, payment.mollie_id ] }
        Organization.define_method(:on_mollie_mandate_created)    { |mandate| calls << [ :mandate_created, mandate.mollie_id ] }
        calls
      end

      def restore_billable_hooks
        BILLABLE_HOOKS.each do |hook|
          Organization.remove_method(hook) if Organization.instance_methods(false).include?(hook)
        end
      end
  end
end
