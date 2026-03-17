class RemoveUniqueConstraintFromWebhookEventMollieId < ActiveRecord::Migration[8.1]
  def up
    remove_index :mollie_pay_webhook_events,
                 name: "index_mollie_pay_webhook_events_on_mollie_id"
  end

  def down
    # Remove duplicates before restoring unique index — keep oldest per mollie_id
    execute <<~SQL
      DELETE FROM mollie_pay_webhook_events
      WHERE id NOT IN (
        SELECT MIN(id) FROM mollie_pay_webhook_events GROUP BY mollie_id
      )
    SQL

    add_index :mollie_pay_webhook_events, :mollie_id,
              unique: true,
              name: "index_mollie_pay_webhook_events_on_mollie_id"
  end
end
