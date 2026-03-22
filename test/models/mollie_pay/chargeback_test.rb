require "test_helper"

module MolliePay
  class ChargebackTest < ActiveSupport::TestCase
    test "reversed? reflects reversed_at" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      assert_not chargeback.reversed?

      chargeback.reversed_at = Time.current
      assert chargeback.reversed?
    end

    test "requires positive amount" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      chargeback.amount = 0
      assert_not chargeback.valid?
    end

    test "requires mollie_id" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      chargeback.mollie_id = nil
      assert_not chargeback.valid?
    end

    test "requires unique mollie_id" do
      existing = mollie_pay_chargebacks(:acme_chargeback)
      duplicate = Chargeback.new(
        payment: existing.payment,
        mollie_id: existing.mollie_id,
        amount: 500,
        currency: "EUR"
      )
      assert_not duplicate.valid?
    end

    test "belongs to payment" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      assert_equal mollie_pay_payments(:acme_first), chargeback.payment
    end

    test "sync_for_payment creates new chargeback from Mollie data" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_chargebacks = [
        stub_mollie_chargeback(id: "chb_new123", amount_value: "10.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks)
      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
      end

      chargeback = Chargeback.find_by(mollie_id: "chb_new123")
      assert_not_nil chargeback
      assert_equal 1000, chargeback.amount
      assert_equal "EUR", chargeback.currency
      assert_equal payment, chargeback.payment
    end

    test "sync_for_payment is idempotent" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_chargebacks = [
        stub_mollie_chargeback(id: "chb_idem123", amount_value: "5.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks)

      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
        assert_equal 1, Chargeback.where(mollie_id: "chb_idem123").count

        Chargeback.sync_for_payment(payment)
        assert_equal 1, Chargeback.where(mollie_id: "chb_idem123").count
      end
    end

    test "sync_for_payment fires on_mollie_chargeback_received for new chargebacks" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_chargebacks = [
        stub_mollie_chargeback(id: "chb_hook123", amount_value: "10.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks)
      hook_called = false
      owner = payment.customer.owner
      owner.define_singleton_method(:on_mollie_chargeback_received) { |_cb| hook_called = true }

      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
      end

      assert hook_called, "on_mollie_chargeback_received should have been called"
    end

    test "sync_for_payment does not fire hook for already processed chargebacks" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_chargebacks = [
        stub_mollie_chargeback(id: "chb_nodup123", amount_value: "10.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks)
      hook_count = 0
      owner = payment.customer.owner
      owner.define_singleton_method(:on_mollie_chargeback_received) { |_cb| hook_count += 1 }

      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
        Chargeback.sync_for_payment(payment)
      end

      assert_equal 1, hook_count, "Hook should fire only once for the same chargeback"
    end

    test "sync_for_payment fires on_mollie_chargeback_reversed when reversed_at is set" do
      payment = mollie_pay_payments(:acme_oneoff)

      # First sync: create chargeback without reversal
      mollie_chargebacks_initial = [
        stub_mollie_chargeback(id: "chb_rev123", amount_value: "10.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks_initial)
      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
      end

      # Second sync: chargeback now has reversed_at
      reversed_time = Time.current
      mollie_chargebacks_reversed = [
        stub_mollie_chargeback(id: "chb_rev123", amount_value: "10.00", amount_currency: "EUR", reversed_at: reversed_time)
      ]

      reversed_hook_called = false
      owner = payment.customer.owner
      owner.define_singleton_method(:on_mollie_chargeback_reversed) { |_cb| reversed_hook_called = true }

      mollie_payment_record_reversed = OpenStruct.new(chargebacks: mollie_chargebacks_reversed)
      payment.stub(:mollie_record, mollie_payment_record_reversed) do
        Chargeback.sync_for_payment(payment)
      end

      assert reversed_hook_called, "on_mollie_chargeback_reversed should have been called"
      assert Chargeback.find_by(mollie_id: "chb_rev123").reversed?
    end

    test "sync_for_payment handles multiple chargebacks" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_chargebacks = [
        stub_mollie_chargeback(id: "chb_multi1", amount_value: "5.00", amount_currency: "EUR"),
        stub_mollie_chargeback(id: "chb_multi2", amount_value: "10.00", amount_currency: "EUR")
      ]

      mollie_payment_record = OpenStruct.new(chargebacks: mollie_chargebacks)
      payment.stub(:mollie_record, mollie_payment_record) do
        Chargeback.sync_for_payment(payment)
      end

      assert Chargeback.exists?(mollie_id: "chb_multi1")
      assert Chargeback.exists?(mollie_id: "chb_multi2")
    end

    test "sync_for_payment does nothing when no chargebacks" do
      payment = mollie_pay_payments(:acme_oneoff)
      mollie_payment_record = OpenStruct.new(chargebacks: [])

      payment.stub(:mollie_record, mollie_payment_record) do
        assert_nothing_raised { Chargeback.sync_for_payment(payment) }
      end
    end

    test "sync_for_payment works with real Mollie SDK objects via WebMock" do
      customer = mollie_pay_customers(:acme)
      payment = mollie_pay_payments(:acme_oneoff)

      hook_called_with = nil
      owner = payment.customer.owner
      owner.define_singleton_method(:on_mollie_chargeback_received) { |cb| hook_called_with = cb }

      webmock_mollie_payment_get_with_chargebacks(payment.mollie_id, customer_id: customer.mollie_id) do
        # Simulate what happens when Payment.record_from_mollie detects a chargeback
        mollie_payment = Mollie::Payment.get(payment.mollie_id)
        Chargeback.sync_for_payment(payment)
      end

      chargeback = Chargeback.find_by(mollie_id: "chb_ls7ahg")
      assert_not_nil chargeback
      assert_equal 1000, chargeback.amount
      assert_equal "EUR", chargeback.currency
      assert_equal payment, chargeback.payment
      assert_not_nil chargeback.created_at_mollie
      assert_equal "Insufficient funds (AM04)", chargeback.reason
      assert_not_nil hook_called_with
      assert_equal chargeback, hook_called_with
    end

    test "amount_decimal converts cents" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      assert_equal 5.0, chargeback.amount_decimal
    end

    test "mollie_amount returns correct hash" do
      chargeback = mollie_pay_chargebacks(:acme_chargeback)
      expected = { currency: "EUR", value: "5.00" }
      assert_equal expected, chargeback.mollie_amount
    end

    private

      def stub_mollie_chargeback(id:, amount_value:, amount_currency:, created_at: nil, reversed_at: nil)
        amount = OpenStruct.new(value: amount_value, currency: amount_currency)
        OpenStruct.new(
          id:          id,
          amount:      amount,
          created_at:  created_at,
          reversed_at: reversed_at
        )
      end
  end
end
