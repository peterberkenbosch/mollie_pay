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
    ensure
      restore_billable_hooks
    end

    test "mandate still pending when first payment is paid becomes valid on a later webhook" do
      payment = create_paybybank_first_payment("tr_pbblate")
      customer = payment.customer
      hooks = record_billable_hooks

      %w[ pending valid ].each do |mandate_status|
        webmock_mollie_payment_get(payment.mollie_id, **paybybank_payment(payment, status: "paid", mandate_id: "mdt_pbblate")) do
          stub_request(:get, "#{MOLLIE_API_BASE}/customers/#{customer.mollie_id}/mandates/mdt_pbblate")
            .to_return(status: 200, body: directdebit_mandate_json("mdt_pbblate", customer, status: mandate_status), headers: { "Content-Type" => "application/hal+json" })

          ProcessWebhookJob.perform_now(payment.mollie_id)
        end

        assert_equal mandate_status, Mandate.find_by!(mollie_id: "mdt_pbblate").status
      end

      assert_not_nil Mandate.find_by!(mollie_id: "mdt_pbblate").mandated_at
      assert_equal [ [ :first_payment_paid, "tr_pbblate" ], [ :mandate_created, "mdt_pbblate" ] ], hooks
    ensure
      restore_billable_hooks
    end

    private

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
