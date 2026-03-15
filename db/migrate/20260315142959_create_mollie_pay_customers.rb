class CreateMolliePayCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_customers do |t|
      t.references :owner, polymorphic: true, null: false, index: { unique: true }
      t.string :mollie_id, null: false, index: { unique: true }
      t.timestamps
    end
  end
end
