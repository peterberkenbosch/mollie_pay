class MakeWebhookEventMollieIdUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :mollie_pay_webhook_events, :mollie_id
    add_index :mollie_pay_webhook_events, :mollie_id, unique: true
  end
end
