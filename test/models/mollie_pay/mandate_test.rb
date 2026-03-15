require "test_helper"

module MolliePay
  class MandateTest < ActiveSupport::TestCase
    test "valid_status? reflects status" do
      assert mollie_pay_mandates(:acme_mandate).valid_status?
    end

    test "valid_status scope returns valid mandates" do
      assert_includes Mandate.valid_status, mollie_pay_mandates(:acme_mandate)
    end

    test "requires valid status" do
      mandate = mollie_pay_mandates(:acme_mandate)
      mandate.status = "nonsense"
      assert_not mandate.valid?
    end

    test "requires method" do
      mandate = mollie_pay_mandates(:acme_mandate)
      mandate.method = nil
      assert_not mandate.valid?
    end

    test "record_from_mollie_payment creates mandate from first payment" do
      payment = mollie_pay_payments(:acme_first)

      mollie_payment = OpenStruct.new(mandate_id: "mdt_new789")
      mollie_mandate = OpenStruct.new(
        id:     "mdt_new789",
        status: "valid",
        method: "creditcard"
      )

      payment.stub(:mollie_record, mollie_payment) do
        Mollie::Customer::Mandate.stub(:get, mollie_mandate) do
          mandate = Mandate.record_from_mollie_payment(payment)

          assert_equal "mdt_new789", mandate.mollie_id
          assert_equal "valid", mandate.status
          assert_equal "creditcard", mandate.method
          assert_not_nil mandate.mandated_at
        end
      end
    end

    test "record_from_mollie_payment calls mandate_created hook" do
      payment = mollie_pay_payments(:acme_first)
      hook_called = false
      owner = payment.customer.owner

      owner.define_singleton_method(:on_mollie_mandate_created) { |_m| hook_called = true }

      mollie_payment = OpenStruct.new(mandate_id: "mdt_hook789")
      mollie_mandate = OpenStruct.new(
        id:     "mdt_hook789",
        status: "valid",
        method: "creditcard"
      )

      payment.stub(:mollie_record, mollie_payment) do
        Mollie::Customer::Mandate.stub(:get, mollie_mandate) do
          Mandate.record_from_mollie_payment(payment)
        end
      end

      assert hook_called
    end

    test "record_from_mollie_payment returns nil without mandate_id" do
      payment = mollie_pay_payments(:acme_first)
      mollie_payment = OpenStruct.new(mandate_id: nil)

      payment.stub(:mollie_record, mollie_payment) do
        assert_nil Mandate.record_from_mollie_payment(payment)
      end
    end
  end
end
