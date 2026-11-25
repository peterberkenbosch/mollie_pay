require "test_helper"

module MolliePay
  class NotifyBillableJobTest < ActiveJob::TestCase
    setup do
      @payment = mollie_pay_payments(:acme_oneoff)
      @owner = @payment.customer.owner
    end

    teardown do
      Organization.remove_method(:on_mollie_payment_paid) if Organization.instance_methods(false).include?(:on_mollie_payment_paid)
    end

    test "calls the hook on the billable with the record" do
      received = []
      Organization.define_method(:on_mollie_payment_paid) { |payment| received << payment }

      NotifyBillableJob.perform_now(@owner, :on_mollie_payment_paid, @payment)

      assert_equal [ @payment ], received
    end

    test "a hook that raises is retried by this job" do
      Organization.define_method(:on_mollie_payment_paid) { |_payment| raise "Mollie unavailable" }

      assert_enqueued_with job: NotifyBillableJob, args: [ @owner, :on_mollie_payment_paid, @payment ] do
        NotifyBillableJob.perform_now(@owner, :on_mollie_payment_paid, @payment)
      end
    end
  end
end
