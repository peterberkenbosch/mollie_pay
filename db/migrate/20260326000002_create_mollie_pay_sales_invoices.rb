class CreateMolliePaySalesInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :mollie_pay_sales_invoices do |t|
      t.references :customer, null: false,
        foreign_key: { to_table: :mollie_pay_customers }
      t.string   :mollie_id,             null: false, index: { unique: true }
      t.string   :status,                null: false, default: "draft"
      t.string   :invoice_number
      t.integer  :amount
      t.string   :currency
      t.string   :recipient_identifier
      t.text     :memo
      t.datetime :issued_at
      t.datetime :paid_at
      t.datetime :due_at
      t.timestamps
    end
  end
end
