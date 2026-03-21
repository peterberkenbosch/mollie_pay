class CreateMolliePayChargebacks < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_chargebacks do |t|
      t.references :payment, null: false,
        foreign_key: { to_table: :mollie_pay_payments }
      t.string   :mollie_id, null: false, index: { unique: true }
      t.integer  :amount,    null: false
      t.string   :currency,  null: false, default: "EUR"
      t.string   :reason
      t.datetime :created_at_mollie
      t.datetime :reversed_at
      t.timestamps
    end
  end
end
