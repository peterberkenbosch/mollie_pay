module MolliePay
  module Billable
    extend ActiveSupport::Concern

    included do
      has_one :mollie_customer,
              class_name: "MolliePay::Customer",
              as:          :owner,
              dependent:   :destroy

      has_many :mollie_subscriptions,
               through:    :mollie_customer,
               source:     :subscriptions,
               class_name: "MolliePay::Subscription"

      has_many :mollie_payments,
               through:    :mollie_customer,
               source:     :payments,
               class_name: "MolliePay::Payment"

      has_many :mollie_mandates,
               through:    :mollie_customer,
               source:     :mandates,
               class_name: "MolliePay::Mandate"
    end

    # === Customer ===

    def mollie_customer!
      mollie_customer || create_mollie_customer_on_mollie
    end

    # === Payments ===

    def mollie_pay_once(amount:, description:, redirect_url: nil, method: nil)
      create_mollie_payment(amount:, description:, redirect_url:, method:, sequence_type: "oneoff")
    end

    def mollie_pay_first(amount:, description:, redirect_url: nil, method: nil)
      create_mollie_payment(amount:, description:, redirect_url:, method:, sequence_type: "first")
    end

    def mollie_subscribe(amount:, interval:, description:, start_date: nil)
      raise MolliePay::MandateRequired, "No valid mandate on file" unless mollie_mandated?

      customer = mollie_customer!
      params = {
        customer_id: customer.mollie_id,
        amount:      mollie_amount(amount),
        interval:    interval,
        description: description,
        webhook_url: MolliePay.configuration.webhook_url
      }
      params[:start_date] = start_date.to_s if start_date
      ms = Mollie::Customer::Subscription.create(**params)
      Subscription.create!(
        customer:  customer,
        mollie_id: ms.id,
        status:    ms.status,
        amount:    amount,
        currency:  MolliePay.configuration.currency,
        interval:  interval
      )
    end

    def mollie_cancel_subscription
      subscription = mollie_subscription
      raise MolliePay::SubscriptionNotFound, "No active subscription" unless subscription

      Mollie::Customer::Subscription.cancel(
        subscription.mollie_id,
        customer_id: mollie_customer.mollie_id
      )
      subscription.update!(status: "canceled", canceled_at: Time.current)
    end

    def mollie_refund(payment, amount: nil)
      amount_cents = amount || payment.amount
      mr = Mollie::Refund.create(
        paymentId: payment.mollie_id,
        amount:    mollie_amount(amount_cents)
      )
      Refund.create!(
        payment:  payment,
        mollie_id: mr.id,
        status:    mr.status,
        amount:    amount_cents,
        currency:  payment.currency
      )
    end

    # === State queries ===

    def mollie_subscribed?
      mollie_subscriptions.active.exists?
    end

    def mollie_mandated?
      mollie_mandates.valid_status.exists?
    end

    def mollie_subscription
      mollie_subscriptions.active.first
    end

    def mollie_mandate
      mollie_mandates.valid_status.first
    end

    # === Hooks — override these in your model ===

    def on_mollie_payment_paid(payment)             ; end
    def on_mollie_payment_failed(payment)           ; end
    def on_mollie_payment_canceled(payment)         ; end
    def on_mollie_payment_expired(payment)          ; end
    def on_mollie_first_payment_paid(payment)       ; end
    def on_mollie_subscription_charged(payment)     ; end
    def on_mollie_subscription_canceled(subscription) ; end
    def on_mollie_subscription_suspended(subscription); end
    def on_mollie_subscription_completed(subscription); end
    def on_mollie_mandate_created(mandate)          ; end
    def on_mollie_refund_processed(refund)          ; end

    private

    def create_mollie_payment(amount:, description:, redirect_url:, method:, sequence_type:)
      customer = mollie_customer!

      Payment.transaction do
        payment = Payment.create!(
          customer:      customer,
          amount:        amount,
          currency:      MolliePay.configuration.currency,
          sequence_type: sequence_type
        )

        resolved_redirect_url = redirect_url || MolliePay.configuration.redirect_url_for(payment)
        raise MolliePay::ConfigurationError, "No redirect_url provided and default_redirect_path is not configured" if resolved_redirect_url.blank?

        mp = Mollie::Payment.create(
          amount:       mollie_amount(amount),
          description:  description,
          redirectUrl:  resolved_redirect_url,
          webhookUrl:   MolliePay.configuration.webhook_url,
          customerId:   customer.mollie_id,
          sequenceType: sequence_type,
          method:       method
        )

        payment.update!(
          mollie_id:    mp.id,
          status:       mp.status,
          checkout_url: mp.checkout_url
        )

        payment
      end
    end

    def create_mollie_customer_on_mollie
      mc = Mollie::Customer.create(
        name:  respond_to?(:name)  ? name  : nil,
        email: respond_to?(:email) ? email : nil
      )
      create_mollie_customer!(mollie_id: mc.id)
    end

    def mollie_amount(cents)
      {
        currency: MolliePay.configuration.currency,
        value:    format("%.2f", cents / 100.0)
      }
    end
  end
end
