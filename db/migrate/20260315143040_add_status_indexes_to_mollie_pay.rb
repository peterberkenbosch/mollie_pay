class AddStatusIndexesToMolliePay < ActiveRecord::Migration[8.1]
  def change
    add_index :mollie_pay_payments, [ :customer_id, :status ]
    add_index :mollie_pay_subscriptions, [ :customer_id, :status ]
    add_index :mollie_pay_mandates, [ :customer_id, :status ]
    add_index :mollie_pay_webhook_events, :processed_at
  end
end
