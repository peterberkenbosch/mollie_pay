class CreateMolliePayChargebacks < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_chargebacks, id: :string do |t|
      t.references :payment, null: false, type: :string,
        foreign_key: { to_table: :mollie_pay_payments }
      t.string   :mollie_id, null: false, index: { unique: true }
      t.string   :amount,    null: false, default: "0" # BigDecimal money as text (see MolliePay::DecimalMoneyType)
      t.string   :currency,  null: false, default: "EUR"
      t.string   :reason
      t.datetime :created_at_mollie
      t.datetime :reversed_at
      t.timestamps
    end
  end
end
