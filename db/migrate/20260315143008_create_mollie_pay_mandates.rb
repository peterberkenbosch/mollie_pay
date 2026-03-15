class CreateMolliePayMandates < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_mandates do |t|
      t.references :customer, null: false,
        foreign_key: { to_table: :mollie_pay_customers }
      t.string :mollie_id, null: false, index: { unique: true }
      t.string :method,    null: false
      t.string :status,    null: false, default: "pending"
      t.datetime :mandated_at
      t.timestamps
    end
  end
end
