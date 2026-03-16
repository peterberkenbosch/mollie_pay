require "test_helper"

module MolliePay
  class BillableTest < ActiveSupport::TestCase
    setup do
      @org = organizations(:acme)
    end

    test "mollie_subscribed? returns true when active subscription exists" do
      assert @org.mollie_subscribed?
    end

    test "mollie_subscribed? returns false without customer" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_not org.mollie_subscribed?
    end

    test "mollie_mandated? returns true when valid mandate exists" do
      assert @org.mollie_mandated?
    end

    test "mollie_mandated? returns false without customer" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_not org.mollie_mandated?
    end

    test "mollie_subscription returns active subscription" do
      assert_equal mollie_pay_subscriptions(:acme_monthly), @org.mollie_subscription
    end

    test "mollie_mandate returns valid mandate" do
      assert_equal mollie_pay_mandates(:acme_mandate), @org.mollie_mandate
    end

    test "mollie_payments returns payments relation" do
      assert_includes @org.mollie_payments, mollie_pay_payments(:acme_first)
    end

    test "mollie_payments returns empty relation without customer" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_equal Payment.none.to_a, org.mollie_payments.to_a
    end

    test "mollie_pay_once creates a one-off payment with checkout_url" do
      stub_mollie_payment_create(id: "tr_oneoff_new") do
        payment = @org.mollie_pay_once(
          amount: 5000,
          description: "One-off charge",
          redirect_url: "https://example.com/return"
        )

        assert_equal "tr_oneoff_new", payment.mollie_id
        assert_equal "open", payment.status
        assert_equal 5000, payment.amount
        assert_equal "oneoff", payment.sequence_type
        assert_equal @org.mollie_customer, payment.customer
        assert payment.checkout_url.present?
      end
    end

    test "mollie_pay_first creates a first payment with checkout_url" do
      stub_mollie_payment_create(id: "tr_first_new") do
        payment = @org.mollie_pay_first(
          amount: 1000,
          description: "Setup fee",
          redirect_url: "https://example.com/return"
        )

        assert_equal "tr_first_new", payment.mollie_id
        assert_equal "open", payment.status
        assert_equal 1000, payment.amount
        assert_equal "first", payment.sequence_type
        assert payment.checkout_url.present?
      end
    end

    test "mollie_pay_once uses default_redirect_url when no redirect_url given" do
      MolliePay.configuration.default_redirect_path = "/payments/complete"

      passed_redirect_url = nil
      response = fake_mollie_payment(id: "tr_default_redir")
      fake_create = ->(**args) { passed_redirect_url = args[:redirectUrl]; response }

      Mollie::Payment.stub(:create, fake_create) do
        payment = @org.mollie_pay_once(amount: 3000, description: "Default redirect")

        assert_equal "tr_default_redir", payment.mollie_id
        assert payment.checkout_url.present?
      end

      assert_equal "https://example.com/payments/complete", passed_redirect_url
    ensure
      MolliePay.configuration.default_redirect_path = nil
    end

    test "mollie_pay_once prefers per-call redirect_url over default" do
      MolliePay.configuration.default_redirect_path = "/default"

      passed_redirect_url = nil
      response = fake_mollie_payment(id: "tr_override")
      fake_create = ->(**args) { passed_redirect_url = args[:redirectUrl]; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_once(
          amount: 2000,
          description: "Override redirect",
          redirect_url: "https://example.com/custom-return"
        )
      end

      assert_equal "https://example.com/custom-return", passed_redirect_url
    ensure
      MolliePay.configuration.default_redirect_path = nil
    end

    test "mollie_pay_once raises when no redirect_url and no default configured" do
      MolliePay.configuration.default_redirect_path = nil

      assert_raises(MolliePay::ConfigurationError) do
        @org.mollie_pay_once(amount: 1000, description: "No redirect")
      end
    end

    test "mollie_pay_once raises when redirect_url is blank string" do
      MolliePay.configuration.default_redirect_path = nil

      assert_raises(MolliePay::ConfigurationError) do
        @org.mollie_pay_once(amount: 1000, description: "Blank redirect", redirect_url: "")
      end
    end

    test "mollie_pay_once creates customer on mollie if none exists" do
      org = Organization.create!(name: "Fresh Org", email: "fresh@org.nl")
      assert_nil org.mollie_customer

      stub_mollie_customer_and_payment_create(
        customer_overrides: { id: "cst_fresh123" },
        payment_overrides:  { id: "tr_fresh_pay" }
      ) do
        payment = org.mollie_pay_once(
          amount: 2500,
          description: "First charge",
          redirect_url: "https://example.com/return"
        )

        assert_not_nil org.reload.mollie_customer
        assert_equal "cst_fresh123", org.mollie_customer.mollie_id
        assert_equal "tr_fresh_pay", payment.mollie_id
        assert payment.checkout_url.present?
      end
    end

    test "mollie_refund creates a full refund" do
      payment = mollie_pay_payments(:acme_oneoff)

      stub_mollie_refund_create(id: "re_full123") do
        refund = @org.mollie_refund(payment)

        assert_equal "re_full123", refund.mollie_id
        assert_equal "queued", refund.status
        assert_equal payment.amount, refund.amount
        assert_equal payment, refund.payment
      end
    end

    test "mollie_refund creates a partial refund" do
      payment = mollie_pay_payments(:acme_oneoff)

      stub_mollie_refund_create(id: "re_partial123") do
        refund = @org.mollie_refund(payment, amount: 2500)

        assert_equal "re_partial123", refund.mollie_id
        assert_equal 2500, refund.amount
      end
    end

    test "mollie_subscribe raises without mandate" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_raises(MolliePay::MandateRequired) do
        org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Plan")
      end
    end

    test "mollie_subscribe creates a subscription" do
      stub_mollie_subscription_create(id: "sub_new123") do
        subscription = @org.mollie_subscribe(
          amount: 2500,
          interval: "1 month",
          description: "Monthly plan"
        )

        assert_equal "sub_new123", subscription.mollie_id
        assert_equal "active", subscription.status
        assert_equal 2500, subscription.amount
        assert_equal "1 month", subscription.interval
      end
    end

    test "mollie_cancel_subscription raises without active subscription" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_raises(MolliePay::SubscriptionNotFound) do
        org.mollie_cancel_subscription
      end
    end

    test "mollie_cancel_subscription cancels the subscription" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      assert subscription.active?

      stub_mollie_subscription_cancel do
        @org.mollie_cancel_subscription
      end

      assert_equal "canceled", subscription.reload.status
      assert_not_nil subscription.canceled_at
    end

    test "on_mollie_* hooks are defined and callable" do
      payment      = mollie_pay_payments(:acme_first)
      subscription = mollie_pay_subscriptions(:acme_monthly)
      mandate      = mollie_pay_mandates(:acme_mandate)
      refund       = mollie_pay_refunds(:acme_refund)

      assert_nothing_raised do
        @org.on_mollie_payment_paid(payment)
        @org.on_mollie_payment_failed(payment)
        @org.on_mollie_payment_canceled(payment)
        @org.on_mollie_payment_expired(payment)
        @org.on_mollie_first_payment_paid(payment)
        @org.on_mollie_subscription_charged(payment)
        @org.on_mollie_subscription_canceled(subscription)
        @org.on_mollie_subscription_suspended(subscription)
        @org.on_mollie_subscription_completed(subscription)
        @org.on_mollie_mandate_created(mandate)
        @org.on_mollie_refund_processed(refund)
      end
    end
  end
end
