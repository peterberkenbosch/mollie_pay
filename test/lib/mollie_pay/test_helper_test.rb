require "test_helper"

module MolliePay
  class TestHelperTest < ActiveSupport::TestCase
    setup do
      @org = organizations(:acme)
    end

    # ── Method-level stubs ───────────────────────────────────────────

    test "stub_mollie_payment_create stubs payment creation" do
      stub_mollie_payment_create do
        payment = @org.mollie_pay_once(amount: 5000, description: "Test", redirect_url: "https://example.com/return")

        assert_equal "open", payment.status
        assert payment.checkout_url.present?
      end
    end

    test "stub_mollie_payment_create accepts overrides" do
      stub_mollie_payment_create(id: "tr_custom", status: "open") do
        payment = @org.mollie_pay_once(amount: 1000, description: "Custom", redirect_url: "https://example.com/return")

        assert_equal "tr_custom", payment.mollie_id
      end
    end

    test "stub_mollie_customer_and_payment_create stubs both" do
      org = Organization.create!(name: "New", email: "new@test.nl")

      stub_mollie_customer_and_payment_create do
        payment = org.mollie_pay_once(amount: 1000, description: "First", redirect_url: "https://example.com/return")

        assert org.reload.mollie_customer.present?
        assert payment.checkout_url.present?
      end
    end

    test "stub_mollie_subscription_create stubs subscription creation" do
      stub_mollie_subscription_create do
        subscription = @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")

        assert_equal "active", subscription.status
      end
    end

    test "stub_mollie_subscription_cancel stubs cancellation" do
      stub_mollie_subscription_cancel do
        @org.mollie_cancel_subscription
      end

      assert_equal "canceled", mollie_pay_subscriptions(:acme_monthly).reload.status
    end

    test "stub_mollie_refund_create stubs refund creation" do
      payment = mollie_pay_payments(:acme_oneoff)

      stub_mollie_refund_create do
        refund = @org.mollie_refund(payment)

        assert_equal "queued", refund.status
      end
    end

    # ── WebMock-based API stubs ──────────────────────────────────────

    test "webmock_mollie_payment_create exercises full SDK pipeline" do
      webmock_mollie_payment_create do
        payment = @org.mollie_pay_once(amount: 1000, description: "WebMock test", redirect_url: "https://example.com/return")

        assert_equal "tr_test1234AB", payment.mollie_id
        assert_equal "open", payment.status
        assert_equal 1000, payment.amount
        assert_equal "https://www.mollie.com/payscreen/select-method/test1234AB", payment.checkout_url
      end
    end

    test "webmock_mollie_payment_create accepts overrides" do
      webmock_mollie_payment_create(id: "tr_custom99", status: "open", amount_value: "50.00") do
        payment = @org.mollie_pay_once(amount: 5000, description: "Custom", redirect_url: "https://example.com/return")

        assert_equal "tr_custom99", payment.mollie_id
      end
    end

    test "webmock_mollie_customer_and_payment_create exercises full pipeline" do
      org = Organization.create!(name: "WebMock Org", email: "wm@test.nl")

      webmock_mollie_customer_and_payment_create do
        payment = org.mollie_pay_once(amount: 2000, description: "Full pipeline", redirect_url: "https://example.com/return")

        assert_equal "cst_test1234AB", org.reload.mollie_customer.mollie_id
        assert_equal "tr_test1234AB", payment.mollie_id
        assert_equal "https://www.mollie.com/payscreen/select-method/test1234AB", payment.checkout_url
      end
    end

    test "webmock_mollie_subscription_create exercises full pipeline" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)
      customer_id = @org.mollie_customer.mollie_id

      webmock_mollie_subscription_create(customer_id: customer_id) do
        subscription = @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Monthly")

        assert_equal "sub_test1234AB", subscription.mollie_id
        assert_equal "active", subscription.status
        assert_equal 2500, subscription.amount
        assert_equal "1 month", subscription.interval
      end
    end

    test "webmock_mollie_subscription_create hits customer-nested endpoint" do
      mollie_pay_subscriptions(:acme_monthly).update!(status: "canceled", canceled_at: Time.current)
      customer_id = @org.mollie_customer.mollie_id
      expected_url = "#{MOLLIE_API_BASE}/customers/#{customer_id}/subscriptions"

      webmock_mollie_subscription_create(customer_id: customer_id) do
        @org.mollie_subscribe(amount: 2500, interval: "1 month", description: "Endpoint test")
        assert_requested :post, expected_url
      end
    end

    test "webmock_mollie_subscription_cancel exercises full pipeline" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      customer_id = @org.mollie_customer.mollie_id

      webmock_mollie_subscription_cancel(customer_id: customer_id, subscription_id: subscription.mollie_id) do
        @org.mollie_cancel_subscription
      end

      assert_equal "canceled", subscription.reload.status
    end

    test "webmock_mollie_subscription_cancel hits customer-nested endpoint" do
      subscription = mollie_pay_subscriptions(:acme_monthly)
      customer_id = @org.mollie_customer.mollie_id
      expected_url = "#{MOLLIE_API_BASE}/customers/#{customer_id}/subscriptions/#{subscription.mollie_id}"

      webmock_mollie_subscription_cancel(customer_id: customer_id, subscription_id: subscription.mollie_id) do
        @org.mollie_cancel_subscription
        assert_requested :delete, expected_url
      end
    end

    test "webmock_mollie_refund_create exercises full pipeline" do
      payment = mollie_pay_payments(:acme_oneoff)

      webmock_mollie_refund_create do
        refund = @org.mollie_refund(payment)

        assert_equal "re_test1234AB", refund.mollie_id
        assert_equal "queued", refund.status
      end
    end

    test "webmock_mollie_payment_get stubs GET for webhook processing" do
      customer = mollie_pay_customers(:acme)

      webmock_mollie_payment_get("tr_webhook123", status: "paid", customer_id: customer.mollie_id) do
        mollie_payment = Mollie::Payment.get("tr_webhook123")

        assert_equal "tr_webhook123", mollie_payment.id
        assert_equal "paid", mollie_payment.status
      end
    end

    # ── Fake builders ────────────────────────────────────────────────

    test "fake_mollie_payment generates unique IDs" do
      a = fake_mollie_payment
      b = fake_mollie_payment

      assert a.id.start_with?("tr_test")
      assert b.id.start_with?("tr_test")
      assert_not_equal a.id, b.id
    end

    test "fake_mollie_payment builds checkout_url from ID" do
      response = fake_mollie_payment(id: "tr_abc")
      assert_equal "https://www.mollie.com/payscreen/select-method/tr_abc", response.checkout_url
    end

    test "fake_mollie_customer generates unique IDs" do
      a = fake_mollie_customer
      b = fake_mollie_customer

      assert a.id.start_with?("cst_test")
      assert_not_equal a.id, b.id
    end

    test "fake_mollie_subscription defaults to active" do
      response = fake_mollie_subscription
      assert_equal "active", response.status
    end

    test "fake_mollie_refund defaults to queued" do
      response = fake_mollie_refund
      assert_equal "queued", response.status
    end
  end
end
