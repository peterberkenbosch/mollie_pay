class DropMolliePayWebhookEvents < ActiveRecord::Migration[8.1]
  def up
    drop_table :mollie_pay_webhook_events
  end

  def down
    create_table :mollie_pay_webhook_events do |t|
      t.string :mollie_id, null: false
      t.string :resource_type
      t.datetime :processed_at
      t.datetime :failed_at
      t.text :error
      t.timestamps
    end

    add_index :mollie_pay_webhook_events, :mollie_id, unique: true
    add_index :mollie_pay_webhook_events, :processed_at
  end
end
