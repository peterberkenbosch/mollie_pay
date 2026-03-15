class CreateMolliePayRefunds < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_refunds do |t|
      t.references :payment, null: false,
        foreign_key: { to_table: :mollie_pay_payments }
      t.string  :mollie_id, null: false, index: { unique: true }
      t.string  :status,    null: false, default: "queued"
      t.integer :amount,    null: false
      t.string  :currency,  null: false, default: "EUR"
      t.datetime :refunded_at
      t.timestamps
    end
  end
end
