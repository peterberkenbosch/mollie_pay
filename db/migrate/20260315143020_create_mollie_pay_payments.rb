class CreateMolliePayPayments < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_payments do |t|
      t.references :customer, null: false,
        foreign_key: { to_table: :mollie_pay_customers }
      t.references :subscription,
        foreign_key: { to_table: :mollie_pay_subscriptions }
      t.string  :mollie_id,     null: false, index: { unique: true }
      t.string  :status,        null: false, default: "open"
      t.integer :amount,        null: false
      t.string  :currency,      null: false, default: "EUR"
      t.string  :sequence_type, null: false, default: "oneoff"
      t.datetime :paid_at
      t.datetime :failed_at
      t.datetime :canceled_at
      t.datetime :expired_at
      t.timestamps
    end
  end
end
