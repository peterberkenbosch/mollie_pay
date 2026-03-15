class CreateMolliePaySubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_subscriptions do |t|
      t.references :customer, null: false,
        foreign_key: { to_table: :mollie_pay_customers }
      t.string  :mollie_id, null: false, index: { unique: true }
      t.string  :status,    null: false, default: "pending"
      t.integer :amount,    null: false
      t.string  :currency,  null: false, default: "EUR"
      t.string  :interval,  null: false
      t.datetime :canceled_at
      t.timestamps
    end
  end
end
