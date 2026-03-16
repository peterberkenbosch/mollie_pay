# Building a SaaS billing app with MolliePay

This tutorial walks you through building a complete billing system for a SaaS
application using MolliePay and vanilla Rails. You'll implement one-off payments,
monthly subscriptions, and yearly subscriptions — all with real Mollie checkout
pages and webhook processing.

**What you'll build:**

- Account signup and login
- One-off payments with Mollie checkout
- Monthly subscription (€25/month)
- Yearly subscription (€250/year)
- Billing dashboard with payment history
- Cancel and resubscribe flows

**Prerequisites:**

- Ruby 3.2+ and Rails 8.0+
- A [Mollie account](https://my.mollie.com/dashboard/signup/7878281?lang=nl) (free to create)
- A Mollie **test** API key (starts with `test_`)
- [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) or [ngrok](https://ngrok.com) for webhook tunneling

**Time:** About 45 minutes.

---

## Part 1: Project setup

### Create the Rails app

```sh
rails new acme_saas --database=sqlite3
cd acme_saas
```

### Add MolliePay

Add to your `Gemfile`:

```ruby
gem "mollie_pay", github: "peterberkenbosch/mollie_pay"
```

Install MolliePay:

```sh
bundle install
bin/rails generate mollie_pay:install
```

This creates the initializer at `config/initializers/mollie_pay.rb`, copies the
migrations, and runs them. Open the generated initializer and review the
defaults — we'll set the environment variables later when we start the server.

### Mount the engine

Add the engine route to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"
end
```

The generated initializer looks like this:

```ruby
MolliePay.configure do |config|
  config.api_key               = ENV["MOLLIE_API_KEY"]
  config.host                  = ENV["MOLLIE_HOST"] # e.g. "https://yourapp.com"
  config.default_redirect_path = "/billing_return"
  config.currency              = "EUR"
end
```

The `host` is used to build the webhook URL automatically from the engine's
mount path. The `default_redirect_path` is combined with `host` to form the
full redirect URL.

### Add authentication

Rails 8 includes a built-in authentication generator:

```sh
bin/rails generate authentication
```

This creates `User`, `Session`, and `Current` models, plus a `SessionsController`
for login. It does **not** create a signup flow — we'll add that next.

Run the generated migration:

```sh
bin/rails db:migrate
```

### Add signup

Create a registrations controller:

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: [ :new, :create ]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      start_new_session_for @user
      redirect_to root_path, notice: "Account created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.expect(user: [ :email_address, :password, :password_confirmation ])
  end
end
```

Create the signup view at `app/views/registrations/new.html.erb`:

```erb
<h1>Sign up</h1>

<%= form_with model: @user, url: registration_path do |form| %>
  <% if @user.errors.any? %>
    <div id="error_explanation">
      <h2><%= pluralize(@user.errors.count, "error") %> prevented signup:</h2>
      <ul>
        <% @user.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= form.label :email_address %>
    <%= form.email_field :email_address, required: true %>
  </div>

  <div>
    <%= form.label :password %>
    <%= form.password_field :password, required: true %>
  </div>

  <div>
    <%= form.label :password_confirmation %>
    <%= form.password_field :password_confirmation, required: true %>
  </div>

  <div>
    <%= form.submit "Sign up" %>
  </div>
<% end %>

<p>Already have an account? <%= link_to "Log in", new_session_path %></p>
```

Add the routes in `config/routes.rb`. The authentication generator already added
a `resource :session` line — keep that and add the registration and root routes:

```ruby
Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"

  resource :registration, only: [ :new, :create ]
  resource :session, only: [ :new, :create, :destroy ]

  root "dashboard#show"
end
```

### Make User billable

Add `MolliePay::Billable` to your `User` model:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include MolliePay::Billable

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: -> (e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
end
```

> **Note:** MolliePay uses a polymorphic association, so it works with any model
> name — `User`, `Account`, `Organization`, `Team`, etc.

### Create the dashboard

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def show
  end
end
```

Create `app/views/dashboard/show.html.erb`:

```erb
<h1>Dashboard</h1>

<p>Welcome, <%= Current.user.email_address %>!</p>

<nav>
  <ul>
    <li><%= link_to "Make a payment", new_payment_path %></li>
    <li><%= link_to "Subscriptions", pricing_path %></li>
    <li><%= link_to "Billing", billing_path %></li>
  </ul>
</nav>
```

Don't worry about the missing routes — we'll add them in the next parts.

---

## Part 2: One-off payments

This is the simplest Mollie flow: create a payment, redirect the customer to
Mollie's checkout page, and handle the return.

### Create the payments controller

```ruby
# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  def new
  end

  def create
    amount      = params.expect(:amount).to_i
    description = params.expect(:description)

    payment = Current.user.mollie_pay_once(
      amount:      amount,
      description: description
    )

    redirect_to payment.checkout_url, allow_other_host: true
  end

  def show
    @payment = Current.user.mollie_payments.find(params[:id])
  end
end
```

> **What's happening:** `mollie_pay_once` creates a payment on Mollie's API,
> stores the local record, and returns it with the `checkout_url` populated.
> We redirect the user to Mollie's hosted payment page. After they complete (or
> abandon) payment, Mollie redirects them back to the `default_redirect_path`.

### Add the views

`app/views/payments/new.html.erb`:

```erb
<h1>Make a payment</h1>

<%= form_with url: payments_path, method: :post do |form| %>
  <div>
    <%= form.label :amount, "Amount (in cents)" %>
    <%= form.number_field :amount, value: 1000, min: 100, step: 100 %>
    <small>e.g. 1000 = €10.00</small>
  </div>

  <div>
    <%= form.label :description %>
    <%= form.text_field :description, value: "Test payment" %>
  </div>

  <div>
    <%= form.submit "Pay with Mollie" %>
  </div>
<% end %>
```

`app/views/payments/show.html.erb`:

```erb
<h1>Payment <%= @payment.mollie_id %></h1>

<dl>
  <dt>Status</dt>
  <dd><%= @payment.status %></dd>

  <dt>Amount</dt>
  <dd>€<%= format("%.2f", @payment.amount_decimal) %></dd>

  <dt>Created</dt>
  <dd><%= @payment.created_at.strftime("%d %b %Y %H:%M") %></dd>

  <% if @payment.paid_at %>
    <dt>Paid at</dt>
    <dd><%= @payment.paid_at.strftime("%d %b %Y %H:%M") %></dd>
  <% end %>
</dl>

<p>
  <% if @payment.status == "open" %>
    <em>Waiting for payment confirmation from Mollie...</em>
    <br>
    <%= link_to "Refresh", payment_path(@payment) %>
  <% elsif @payment.paid? %>
    <strong>Payment successful!</strong>
  <% else %>
    Payment status: <%= @payment.status %>
  <% end %>
</p>

<p><%= link_to "Back to dashboard", root_path %></p>
```

### Add routes

Update `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"

  resource :registration, only: [ :new, :create ]
  resource :session, only: [ :new, :create, :destroy ]

  resources :payments, only: [ :new, :create, :show ]

  root "dashboard#show"
end
```

### Add the return controller

When Mollie redirects the customer back to your `default_redirect_path`, you need
a page to land on. Create a simple return handler:

```ruby
# app/controllers/billing_returns_controller.rb
class BillingReturnsController < ApplicationController
  def show
    # Find the most recent payment for this user
    @payment = Current.user.mollie_payments.order(created_at: :desc).first
  end
end
```

`app/views/billing_returns/show.html.erb`:

```erb
<h1>Payment received</h1>

<% if @payment %>
  <p>
    Your payment (<%= @payment.mollie_id %>) is currently
    <strong><%= @payment.status %></strong>.
  </p>

  <% if @payment.status == "open" %>
    <p>
      <em>Mollie is still processing your payment. This usually takes a few
      seconds.</em>
    </p>
    <p><%= link_to "Refresh", billing_return_path %></p>
  <% elsif @payment.paid? %>
    <p>Thank you! Your payment has been confirmed.</p>
  <% end %>

  <p><%= link_to "View payment details", payment_path(@payment) %></p>
<% else %>
  <p>No recent payment found.</p>
<% end %>

<p><%= link_to "Back to dashboard", root_path %></p>
```

Add the route:

```ruby
resource :billing_return, only: :show
```

> **Why the status might still be "open":** Mollie redirects the customer back
> *before* the webhook fires. The customer returns to your app, but the payment
> status update arrives asynchronously via the webhook. This is by design — the
> webhook is the source of truth, not the redirect.

---

## Part 3: Subscriptions

Mollie recurring billing works in two steps:

1. **First payment** — establishes a *mandate* (permission to charge the
   customer's payment method in the future)
2. **Subscription** — uses the mandate to charge automatically on a schedule

You cannot create a subscription without a valid mandate. The mandate is created
automatically when the first payment is completed.

### Add plan columns to User

We need to track what plan the user selected so we know what to subscribe them
to after the mandate is established:

```sh
bin/rails generate migration AddPlanToUsers plan:string
bin/rails db:migrate
```

### Create the pricing page

```ruby
# app/controllers/pricing_controller.rb
class PricingController < ApplicationController
  PLANS = {
    "monthly" => { amount: 2500,  interval: "1 month",   label: "Monthly",  price: "€25/month" },
    "yearly"  => { amount: 25000, interval: "12 months", label: "Yearly",   price: "€250/year (save €50)" }
  }.freeze

  def show
    @plans = PLANS
    @current_subscription = Current.user.mollie_subscription
  end
end
```

`app/views/pricing/show.html.erb`:

```erb
<h1>Choose your plan</h1>

<% if Current.user.mollie_subscribed? %>
  <p>
    You're currently subscribed to the <strong><%= Current.user.plan %></strong> plan.
    <%= link_to "Manage subscription", billing_path %>
  </p>
<% else %>
  <% @plans.each do |key, plan| %>
    <div style="border: 1px solid #ccc; padding: 1em; margin: 1em 0;">
      <h2><%= plan[:label] %></h2>
      <p><strong><%= plan[:price] %></strong></p>

      <% if Current.user.mollie_mandated? %>
        <%= button_to "Subscribe",
              subscriptions_path,
              params: { plan: key },
              method: :post %>
      <% else %>
        <%= button_to "Get started",
              subscription_setup_path,
              params: { plan: key },
              method: :post %>
      <% end %>
    </div>
  <% end %>

  <% unless Current.user.mollie_mandated? %>
    <p>
      <small>
        A small first payment (€0.01) establishes your payment method.
        Your subscription starts after this payment is confirmed.
      </small>
    </p>
  <% end %>
<% end %>
```

> **Two buttons:** If the user already has a mandate (from a previous payment),
> they can subscribe directly. If not, they go through the first payment flow.

### Subscription setup (first payment for mandate)

```ruby
# app/controllers/subscription_setups_controller.rb
class SubscriptionSetupsController < ApplicationController
  def create
    plan = params[:plan]
    unless PricingController::PLANS.key?(plan)
      redirect_to pricing_path, alert: "Invalid plan."
      return
    end

    # Store the chosen plan so we can subscribe after the mandate is established
    Current.user.update!(plan: plan)

    # Create a first payment to establish the mandate
    # Using €0.01 — the minimum amount Mollie accepts
    payment = Current.user.mollie_pay_first(
      amount:      1,
      description: "Payment method setup for #{PricingController::PLANS[plan][:label]} plan"
    )

    redirect_to payment.checkout_url, allow_other_host: true
  end
end
```

> **Why €0.01?** The first payment's purpose is to create a mandate — permission
> to charge the customer's payment method in the future. The amount can be
> anything. We use the minimum so the customer isn't surprised by a charge.

### Subscriptions controller

```ruby
# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  def create
    plan_key = params[:plan] || Current.user.plan
    plan = PricingController::PLANS[plan_key]

    unless plan
      redirect_to pricing_path, alert: "Invalid plan."
      return
    end

    unless Current.user.mollie_mandated?
      redirect_to pricing_path, alert: "Please complete a first payment to set up your payment method."
      return
    end

    Current.user.update!(plan: plan_key)

    Current.user.mollie_subscribe(
      amount:      plan[:amount],
      interval:    plan[:interval],
      description: "Acme SaaS #{plan[:label]} subscription"
    )

    redirect_to billing_path, notice: "Subscription activated!"
  end

  def destroy
    Current.user.mollie_cancel_subscription
    redirect_to billing_path, notice: "Subscription canceled."
  rescue MolliePay::SubscriptionNotFound
    redirect_to billing_path, alert: "No active subscription to cancel."
  end
end
```

### Add routes

Update `config/routes.rb` with all the new routes:

```ruby
Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"

  resource  :registration, only: [ :new, :create ]
  resource  :session, only: [ :new, :create, :destroy ]

  resources :payments, only: [ :new, :create, :show ]
  resource  :billing_return, only: :show
  resource  :pricing, only: :show
  resource  :subscription_setup, only: :create
  resource  :subscription, only: [ :create, :destroy ]
  resource  :billing, only: :show

  root "dashboard#show"
end
```

### Handle the mandate webhook

When the first payment completes, Mollie fires a webhook. MolliePay processes it
and calls the `on_mollie_first_payment_paid` hook on your model. This is where
you can notify the user or auto-subscribe them.

For this tutorial, we'll keep it simple — the user returns from Mollie, sees that
their mandate is established, and clicks "Subscribe" on the pricing page.

But if you want to auto-subscribe, add this to your `User` model:

```ruby
# app/models/user.rb (optional — auto-subscribe after first payment)
def on_mollie_first_payment_paid(payment)
  return unless plan.present?

  plan_details = PricingController::PLANS[plan]
  return unless plan_details

  mollie_subscribe(
    amount:      plan_details[:amount],
    interval:    plan_details[:interval],
    description: "Acme SaaS #{plan_details[:label]} subscription"
  )
end
```

> **Important:** This hook runs in a background job (via Active Job), not in the
> user's HTTP request. That's why we stored the plan on the User model — the hook
> needs to know which plan was chosen.

---

## Part 4: Billing dashboard

Create a billing page where users can see their subscription status, payment
history, and manage their subscription.

```ruby
# app/controllers/billings_controller.rb
class BillingsController < ApplicationController
  def show
    @subscription = Current.user.mollie_subscription
    @mandate      = Current.user.mollie_mandate
    @payments     = Current.user.mollie_payments.order(created_at: :desc).limit(10)
  end
end
```

`app/views/billings/show.html.erb`:

```erb
<h1>Billing</h1>

<h2>Subscription</h2>

<% if @subscription&.active? %>
  <dl>
    <dt>Plan</dt>
    <dd><%= Current.user.plan&.capitalize || "Active" %></dd>

    <dt>Status</dt>
    <dd><%= @subscription.status %></dd>

    <dt>Amount</dt>
    <dd>€<%= format("%.2f", @subscription.amount_decimal) %> / <%= @subscription.interval %></dd>
  </dl>

  <%= button_to "Cancel subscription", subscription_path, method: :delete,
        data: { turbo_confirm: "Are you sure you want to cancel?" } %>
<% else %>
  <p>No active subscription. <%= link_to "View plans", pricing_path %></p>
<% end %>

<h2>Payment method</h2>

<% if @mandate %>
  <dl>
    <dt>Method</dt>
    <dd><%= @mandate.method %></dd>

    <dt>Status</dt>
    <dd><%= @mandate.status %></dd>
  </dl>
<% else %>
  <p>No payment method on file.</p>
<% end %>

<h2>Payment history</h2>

<% if @payments.any? %>
  <table>
    <thead>
      <tr>
        <th>Date</th>
        <th>Payment ID</th>
        <th>Amount</th>
        <th>Status</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <% @payments.each do |payment| %>
        <tr>
          <td><%= payment.created_at.strftime("%d %b %Y") %></td>
          <td><%= payment.mollie_id %></td>
          <td>€<%= format("%.2f", payment.amount_decimal) %></td>
          <td><%= payment.status %></td>
          <td><%= link_to "View", payment_path(payment) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
<% else %>
  <p>No payments yet.</p>
<% end %>

<p><%= link_to "Back to dashboard", root_path %></p>
```

---

## Part 5: Running it locally

### Start a tunnel

Mollie needs to reach your local server to send webhooks. Open a new terminal
and start a tunnel:

**Using cloudflared (no account needed):**

```sh
cloudflared tunnel --url localhost:3000
```

This gives you a URL like `https://random-words.trycloudflare.com`.

**Using ngrok:**

```sh
ngrok http 3000
```

This gives you a URL like `https://xxxx.ngrok-free.app`.

### Allow the tunnel host

Add the tunnel hostname to `config/environments/development.rb`:

```ruby
# For cloudflared:
config.hosts << /.*\.trycloudflare\.com/

# Or for ngrok:
# config.hosts << /.*\.ngrok-free\.app/
```

### Set environment variables

Get your test API key from the [Mollie Dashboard](https://my.mollie.com/dashboard/signup/7878281?lang=nl)
under Developers → API keys.

```sh
export MOLLIE_API_KEY="test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
export MOLLIE_HOST="https://your-tunnel-url.trycloudflare.com"
```

> **Replace** `your-tunnel-url.trycloudflare.com` with your actual tunnel URL.
> The webhook URL and redirect URL are derived automatically from the host.

### Start the server

```sh
bin/rails server
```

### Test the flow

1. **Sign up** at `http://localhost:3000/registration/new`

2. **Make a one-off payment:**
   - Click "Make a payment" on the dashboard
   - Enter an amount (e.g., 1000 for €10.00) and a description
   - Click "Pay with Mollie"
   - You'll be redirected to Mollie's **test checkout** page
   - Select a payment method and status (click "Paid")
   - You'll be redirected back to your app

3. **Subscribe to a plan:**
   - Click "Subscriptions" on the dashboard
   - Choose Monthly (€25/month) or Yearly (€250/year)
   - Click "Get started" — this creates a €0.01 first payment
   - Complete the payment on Mollie's test checkout (click "Paid")
   - Return to your app and go to the pricing page
   - Your mandate is now established — click "Subscribe"

4. **Check the billing dashboard:**
   - Click "Billing" to see your subscription and payment history

5. **Cancel subscription:**
   - On the billing page, click "Cancel subscription"

### Understanding test mode

In Mollie test mode:
- Payments don't actually charge anything
- The checkout page shows status buttons (Paid, Failed, Canceled, Expired)
  instead of real payment forms
- You manually choose the outcome to test different scenarios
- Webhooks fire just like in production

### Checking webhook processing

Watch your Rails server logs. When Mollie sends a webhook, you'll see:

```
Started POST "/mollie_pay/webhooks" for 127.0.0.1
Processing by MolliePay::WebhooksController#create as */*
  Parameters: {"id"=>"tr_xxxxxxxx"}
[ActiveJob] Enqueued MolliePay::ProcessWebhookJob
```

And when the job processes:

```
[ActiveJob] Performing MolliePay::ProcessWebhookJob
[ActiveJob] Performed MolliePay::ProcessWebhookJob
```

---

## Complete routes file

Here's the final `config/routes.rb` for reference:

```ruby
Rails.application.routes.draw do
  mount MolliePay::Engine => "/mollie_pay"

  resource  :registration, only: [ :new, :create ]
  resource  :session, only: [ :new, :create, :destroy ]

  resources :payments, only: [ :new, :create, :show ]
  resource  :billing_return, only: :show
  resource  :pricing, only: :show
  resource  :subscription_setup, only: :create
  resource  :subscription, only: [ :create, :destroy ]
  resource  :billing, only: :show

  root "dashboard#show"
end
```

---

## Going further

### Auto-subscribe after first payment

Instead of making the user click "Subscribe" after their mandate is established,
you can auto-subscribe in the webhook hook:

```ruby
# app/models/user.rb
def on_mollie_first_payment_paid(payment)
  return unless plan.present?

  plan_details = PricingController::PLANS[plan]
  return unless plan_details

  mollie_subscribe(
    amount:      plan_details[:amount],
    interval:    plan_details[:interval],
    description: "Acme SaaS #{plan_details[:label]} subscription"
  )
end
```

This runs in the background via Active Job when Mollie confirms the first
payment. The user's plan was stored on their record when they clicked
"Get started", so the hook knows which plan to activate.

### Plan upgrades and downgrades

To switch plans, cancel the current subscription and create a new one:

```ruby
Current.user.mollie_cancel_subscription
Current.user.mollie_subscribe(
  amount:      new_plan[:amount],
  interval:    new_plan[:interval],
  description: "Acme SaaS #{new_plan[:label]} subscription"
)
```

Mollie handles proration at the payment level — the next charge will be for the
new amount on the new interval.

### Refunds

Refund a payment from the billing dashboard or an admin panel:

```ruby
Current.user.mollie_refund(payment)              # full refund
Current.user.mollie_refund(payment, amount: 500) # partial — €5.00
```

### Production deployment

Before going live:

1. Switch to a `live_` API key
2. Set `host` to your real domain with HTTPS (e.g. `https://yourapp.com`)
3. Configure a proper queue backend (Solid Queue, Sidekiq, etc.)
4. Add rate limiting to the webhook endpoint (see README)
5. Set up monitoring for failed webhook jobs
