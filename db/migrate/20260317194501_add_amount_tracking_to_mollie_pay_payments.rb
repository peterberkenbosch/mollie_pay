class AddAmountTrackingToMolliePayPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :mollie_pay_payments, :amount_refunded, :integer, default: 0
    add_column :mollie_pay_payments, :amount_remaining, :integer
    add_column :mollie_pay_payments, :amount_captured, :integer, default: 0
    add_column :mollie_pay_payments, :amount_charged_back, :integer, default: 0
  end
end
