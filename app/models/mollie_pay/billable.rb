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

    def mollie_update_customer(name: nil, email: nil, locale: nil, metadata: nil)
      raise MolliePay::Error, "No Mollie customer exists" if mollie_customer.nil?

      params = {}
      params[:name]     = name     if name
      params[:email]    = email    if email
      params[:locale]   = locale   if locale
      params[:metadata] = metadata if metadata
      return mollie_customer if params.empty?

      Mollie::Customer.update(mollie_customer.mollie_id, params)
      mollie_customer
    end

    def mollie_delete_customer
      raise MolliePay::Error, "No Mollie customer exists" if mollie_customer.nil?

      Mollie::Customer.delete(mollie_customer.mollie_id)
      mollie_customer.destroy!
    end

    # === Payments ===

    def mollie_pay_once(amount:, description:, redirect_url: nil, method: nil, metadata: nil)
      create_mollie_payment(amount:, description:, redirect_url:, method:, metadata:, sequence_type: "oneoff")
    end

    def mollie_pay_first(amount:, description:, redirect_url: nil, method: nil, metadata: nil)
      create_mollie_payment(amount:, description:, redirect_url:, method:, metadata:, sequence_type: "first")
    end

    def mollie_subscribe(amount:, interval:, description:, start_date: nil, name: "default")
      raise MolliePay::MandateRequired, "No valid mandate on file" unless mollie_mandated?

      existing = mollie_subscriptions.where(status: Subscription::ACTIVE_STATUSES, name: name).first
      return existing if existing

      customer = mollie_customer!
      params = {
        customer_id: customer.mollie_id,
        amount:      mollie_amount(amount),
        interval:    interval,
        description: description,
        webhook_url: MolliePay.configuration.webhook_url,
        metadata:    { mollie_pay_name: name }
      }
      params[:start_date] = start_date.to_s if start_date
      ms = Mollie::Customer::Subscription.create(**params, idempotency_key: SecureRandom.uuid)
      Subscription.create!(
        customer:  customer,
        mollie_id: ms.id,
        status:    ms.status,
        amount:    amount,
        currency:  MolliePay.configuration.currency,
        interval:  interval,
        name:      name
      )
    rescue ActiveRecord::RecordNotUnique
      Mollie::Customer::Subscription.cancel(ms.id, customer_id: customer.mollie_id)
      mollie_subscriptions.where(status: Subscription::ACTIVE_STATUSES, name: name).first!
    end

    def mollie_cancel_subscription(name: "default")
      subscription = mollie_subscriptions.active.named(name).first
      raise MolliePay::SubscriptionNotFound, "No active subscription" unless subscription

      Mollie::Customer::Subscription.cancel(
        subscription.mollie_id,
        customer_id: mollie_customer.mollie_id
      )
      subscription.update!(status: "canceled", canceled_at: Time.current)
    end

    def mollie_swap_subscription(name: "default", amount: nil, interval: nil)
      subscription = mollie_subscriptions.where(status: Subscription::ACTIVE_STATUSES).named(name).first
      raise MolliePay::SubscriptionNotFound, "No active subscription" unless subscription

      params = {}
      params[:amount]   = mollie_amount(amount) if amount && amount != subscription.amount
      params[:interval] = interval              if interval && interval != subscription.interval
      return subscription if params.empty?

      previous_amount   = subscription.amount
      previous_interval = subscription.interval

      Mollie::Customer::Subscription.update(
        subscription.mollie_id,
        customer_id: mollie_customer.mollie_id,
        **params
      )

      subscription.update!(
        amount:   amount || subscription.amount,
        interval: interval || subscription.interval
      )

      on_mollie_subscription_swapped(
        subscription,
        previous_amount: previous_amount,
        previous_interval: previous_interval
      )

      subscription
    end

    def mollie_update_payment(payment, description: nil, redirect_url: nil, metadata: nil)
      verify_payment_ownership!(payment)

      params = {}
      params[:description] = description  if description
      params[:redirectUrl] = redirect_url if redirect_url
      params[:metadata]    = metadata     if metadata
      return payment if params.empty?

      Mollie::Payment.update(payment.mollie_id, params)
      payment
    end

    def mollie_cancel_payment(payment)
      verify_payment_ownership!(payment)

      mollie_payment = Mollie::Payment.get(payment.mollie_id)
      raise MolliePay::PaymentNotCancelable, "Payment #{payment.mollie_id} is not cancelable" unless mollie_payment.cancelable?

      Mollie::Payment.delete(payment.mollie_id)
      payment.update!(status: "canceled", canceled_at: Time.current) unless payment.canceled_at
      payment
    end

    def mollie_refund(payment, amount: nil)
      verify_payment_ownership!(payment)
      amount_cents = amount || payment.amount
      mr = Mollie::Refund.create(
        paymentId:      payment.mollie_id,
        amount:         mollie_amount(amount_cents),
        idempotency_key: SecureRandom.uuid
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

    def mollie_subscribed?(name: "default")
      mollie_subscriptions.active.named(name).exists?
    end

    def mollie_mandated?
      mollie_mandates.valid_status.exists?
    end

    def mollie_subscription(name: "default")
      mollie_subscriptions.active.named(name).first
    end

    def mollie_mandate
      mollie_mandates.valid_status.first
    end

    def mollie_payment_methods(**options)
      MolliePay.payment_methods(**options)
    end

    # === Sales Invoices (beta) ===

    def mollie_create_sales_invoice(lines:, status: "draft", recipient: nil, **options)
      resolved_recipient = recipient || build_sales_invoice_recipient
      MolliePay.create_sales_invoice(status: status, recipient: resolved_recipient, lines: lines, **options)
    end

    def mollie_sales_invoices(**options)
      MolliePay.sales_invoices(**options)
    end

    def mollie_sales_invoice(id)
      MolliePay.sales_invoice(id)
    end

    # === Hooks — override these in your model ===

    def on_mollie_payment_paid(payment)             ; end
    def on_mollie_payment_authorized(payment)       ; end
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
    def on_mollie_chargeback_received(chargeback)  ; end
    def on_mollie_chargeback_reversed(chargeback)  ; end
    def on_mollie_subscription_swapped(subscription, previous_amount:, previous_interval:) ; end

    private

    def verify_payment_ownership!(payment)
      raise MolliePay::Error, "Payment does not belong to this customer" unless mollie_payments.exists?(id: payment.id)
    end

    def create_mollie_payment(amount:, description:, redirect_url:, method:, metadata:, sequence_type:)
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
          amount:          mollie_amount(amount),
          description:     description,
          redirectUrl:     resolved_redirect_url,
          webhookUrl:      MolliePay.configuration.webhook_url,
          customerId:      customer.mollie_id,
          sequenceType:    sequence_type,
          method:          method,
          metadata:        metadata,
          idempotency_key: SecureRandom.uuid
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
        name:            respond_to?(:name)  ? name  : nil,
        email:           respond_to?(:email) ? email : nil,
        idempotency_key: SecureRandom.uuid
      )
      create_mollie_customer!(mollie_id: mc.id)
    end

    def build_sales_invoice_recipient
      if respond_to?(:organization_name) && organization_name.present?
        { type: "business", organization_name: organization_name }.tap do |r|
          r[:email]      = email      if respond_to?(:email) && email.present?
          r[:vat_number] = vat_number if respond_to?(:vat_number) && vat_number.present?
        end
      else
        {}.tap do |r|
          r[:type]        = "consumer"
          r[:given_name]  = name       if respond_to?(:name) && name.present?
          r[:email]       = email      if respond_to?(:email) && email.present?
        end
      end
    end

    def mollie_amount(cents)
      {
        currency: MolliePay.configuration.currency,
        value:    format("%.2f", cents / 100.0)
      }
    end
  end
end
