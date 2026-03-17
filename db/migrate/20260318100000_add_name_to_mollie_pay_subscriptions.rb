class AddNameToMolliePaySubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :mollie_pay_subscriptions, :name, :string, null: false, default: "default"

    # Partial unique index: one active/pending subscription per name per customer.
    # Must match Subscription::ACTIVE_STATUSES constant.
    add_index :mollie_pay_subscriptions, [ :customer_id, :name ],
              unique: true,
              where: "status IN ('pending', 'active')",
              name: "idx_mollie_subs_unique_active_per_customer_name"
  end
end
