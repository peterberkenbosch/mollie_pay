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

    test "mollie_pay_once uses default_redirect_path with :id interpolation when no redirect_url given" do
      MolliePay.configuration.default_redirect_path = "/payments/:id"

      passed_redirect_url = nil
      response = fake_mollie_payment(id: "tr_default_redir")
      fake_create = ->(**args) { passed_redirect_url = args[:redirectUrl]; response }

      Mollie::Payment.stub(:create, fake_create) do
        payment = @org.mollie_pay_once(amount: 3000, description: "Default redirect")

        assert_equal "tr_default_redir", payment.mollie_id
        assert payment.checkout_url.present?
        assert_equal "https://example.com/payments/#{payment.id}", passed_redirect_url
      end
    ensure
      MolliePay.configuration.default_redirect_path = nil
    end

    test "mollie_pay_once prefers per-call redirect_url over default" do
      MolliePay.configuration.default_redirect_path = "/payments/:id"

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

    test "mollie_pay_once passes method to Mollie API when provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_method_once")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_once(
          amount: 3000,
          description: "iDEAL payment",
          redirect_url: "https://example.com/return",
          method: "ideal"
        )
      end

      assert_equal "ideal", received_args[:method]
    end

    test "mollie_pay_first passes method to Mollie API when provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_method_first")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_first(
          amount: 1000,
          description: "First iDEAL",
          redirect_url: "https://example.com/return",
          method: "ideal"
        )
      end

      assert_equal "ideal", received_args[:method]
      assert_equal "first", received_args[:sequenceType]
    end

    test "mollie_pay_once passes nil method when not provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_no_method")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_once(
          amount: 3000,
          description: "No method specified",
          redirect_url: "https://example.com/return"
        )
      end

      assert_nil received_args[:method]
    end

    test "mollie_pay_once passes metadata to Mollie API when provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_meta_once")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_once(
          amount: 3000,
          description: "With metadata",
          redirect_url: "https://example.com/return",
          metadata: { plan: "yearly", source: "checkout" }
        )
      end

      assert_equal({ plan: "yearly", source: "checkout" }, received_args[:metadata])
    end

    test "mollie_pay_first passes metadata to Mollie API when provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_meta_first")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_first(
          amount: 1000,
          description: "First with metadata",
          redirect_url: "https://example.com/return",
          metadata: { plan: "monthly" }
        )
      end

      assert_equal({ plan: "monthly" }, received_args[:metadata])
      assert_equal "first", received_args[:sequenceType]
    end

    test "mollie_pay_once passes nil metadata when not provided" do
      received_args = nil
      response = fake_mollie_payment(id: "tr_no_meta")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Payment.stub(:create, fake_create) do
        @org.mollie_pay_once(
          amount: 3000,
          description: "No metadata",
          redirect_url: "https://example.com/return"
        )
      end

      assert_nil received_args[:metadata]
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

    test "mollie_subscribe returns existing active subscription" do
      existing = mollie_pay_subscriptions(:acme_monthly)
      assert_equal "active", existing.status

      result = @org.mollie_subscribe(
        amount: 5000,
        interval: "1 year",
        description: "Different plan"
      )

      assert_equal existing, result
    end

    test "mollie_subscribe returns existing pending subscription" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      subscription.update!(status: "pending")

      result = @org.mollie_subscribe(
        amount: 2500,
        interval: "1 month",
        description: "Monthly plan"
      )

      assert_equal subscription, result
    end

    test "mollie_subscribe creates new when only canceled subscriptions exist" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      stub_mollie_subscription_create(id: "sub_after_cancel") do
        subscription = @org.mollie_subscribe(
          amount: 2500,
          interval: "1 month",
          description: "Re-subscribe"
        )

        assert_equal "sub_after_cancel", subscription.mollie_id
        assert_equal "active", subscription.status
      end
    end

    test "mollie_subscribe raises without mandate" do
      org = Organization.create!(name: "New Org", email: "new@org.nl")
      assert_raises(MolliePay::MandateRequired) do
        org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Plan")
      end
    end

    test "mollie_subscribe creates a subscription" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

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

    test "mollie_subscribe calls Mollie::Customer::Subscription.create with customer_id" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      received_args = nil
      response = fake_mollie_subscription(id: "sub_api_class_test")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Customer::Subscription.stub(:create, fake_create) do
        @org.mollie_subscribe(
          amount: 2500,
          interval: "1 month",
          description: "API class test"
        )
      end

      assert_not_nil received_args, "Mollie::Customer::Subscription.create was not called"
      assert_equal @org.mollie_customer.mollie_id, received_args[:customer_id]
      assert_equal({ currency: "EUR", value: "25.00" }, received_args[:amount])
      assert_equal "1 month", received_args[:interval]
      assert_equal "API class test", received_args[:description]
    end

    test "mollie_subscribe does not call top-level Mollie::Subscription" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)

      called = false
      top_level_create = ->(**_args) { called = true; fake_mollie_subscription }

      # Stub the correct class to succeed
      response = fake_mollie_subscription(id: "sub_correct")
      Mollie::Customer::Subscription.stub(:create, response) do
        # Stub the wrong class to detect if it's called
        Mollie::Subscription.stub(:create, top_level_create) do
          @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Test")
        end
      end

      assert_not called, "Top-level Mollie::Subscription.create should not be called"
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

    test "mollie_cancel_subscription calls Mollie::Customer::Subscription.cancel" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      received_id = nil
      received_options = nil
      fake_cancel = ->(id, **opts) { received_id = id; received_options = opts; nil }

      Mollie::Customer::Subscription.stub(:cancel, fake_cancel) do
        @org.mollie_cancel_subscription
      end

      assert_equal subscription.mollie_id, received_id
      assert_equal @org.mollie_customer.mollie_id, received_options[:customer_id]
    end

    # === Named subscriptions ===

    test "mollie_subscribe creates named subscription" do
      stub_mollie_subscription_create(id: "sub_new_addon") do
        subscription = @org.mollie_subscribe(
          amount: 1000,
          interval: "1 month",
          description: "Analytics addon",
          name: "reporting"
        )

        assert_equal "sub_new_addon", subscription.mollie_id
        assert_equal "reporting", subscription.name
      end
    end

    test "mollie_subscribe passes name in Mollie metadata" do
      received_args = nil
      response = fake_mollie_subscription(id: "sub_meta_test")
      fake_create = ->(**args) { received_args = args; response }

      Mollie::Customer::Subscription.stub(:create, fake_create) do
        @org.mollie_subscribe(
          amount: 1000,
          interval: "1 month",
          description: "With metadata",
          name: "reporting"
        )
      end

      assert_equal({ mollie_pay_name: "reporting" }, received_args[:metadata])
    end

    test "mollie_subscribe idempotency guard is scoped by name" do
      # acme_monthly (default) and acme_addon (analytics_addon) are both active
      assert @org.mollie_subscribed?(name: "default")
      assert @org.mollie_subscribed?(name: "analytics_addon")

      # Creating a new name should work (not return existing default)
      stub_mollie_subscription_create(id: "sub_new_name") do
        subscription = @org.mollie_subscribe(
          amount: 500,
          interval: "1 month",
          description: "New addon",
          name: "reporting"
        )

        assert_equal "sub_new_name", subscription.mollie_id
        assert_equal "reporting", subscription.name
      end
    end

    test "mollie_subscribe returns existing for same name" do
      existing = mollie_pay_subscriptions(:acme_addon)
      assert_equal "analytics_addon", existing.name

      result = @org.mollie_subscribe(
        amount: 9999,
        interval: "1 year",
        description: "Different params",
        name: "analytics_addon"
      )

      assert_equal existing, result
    end

    test "mollie_subscribed? scoped by name" do
      assert @org.mollie_subscribed?(name: "default")
      assert @org.mollie_subscribed?(name: "analytics_addon")
      assert_not @org.mollie_subscribed?(name: "nonexistent")
    end

    test "mollie_subscription scoped by name" do
      assert_equal mollie_pay_subscriptions(:acme_monthly), @org.mollie_subscription(name: "default")
      assert_equal mollie_pay_subscriptions(:acme_addon), @org.mollie_subscription(name: "analytics_addon")
      assert_nil @org.mollie_subscription(name: "nonexistent")
    end

    test "mollie_cancel_subscription cancels named subscription" do
      addon = mollie_pay_subscriptions(:acme_addon)
      assert addon.active?

      fake_cancel = ->(id, **_opts) { nil }
      Mollie::Customer::Subscription.stub(:cancel, fake_cancel) do
        @org.mollie_cancel_subscription(name: "analytics_addon")
      end

      assert_equal "canceled", addon.reload.status
      assert_not_nil addon.canceled_at
      # Default subscription should still be active
      assert @org.mollie_subscribed?(name: "default")
    end

    test "mollie_cancel_subscription raises for nonexistent name" do
      assert_raises(MolliePay::SubscriptionNotFound) do
        @org.mollie_cancel_subscription(name: "nonexistent")
      end
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
