class CreateMolliePayWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_webhook_events do |t|
      t.string   :mollie_id,    null: false, index: true
      t.string   :resource_type
      t.datetime :processed_at
      t.datetime :failed_at
      t.text     :error
      t.timestamps
    end
  end
end
