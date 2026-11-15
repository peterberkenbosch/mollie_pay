class AddAmountTrackingToMolliePayPayments < ActiveRecord::Migration[8.0]
  def change
    # money as text until ChangeMolliePayMoneyToDecimal makes it decimal(15,4)
    add_column :mollie_pay_payments, :amount_refunded, :string, default: "0"
    add_column :mollie_pay_payments, :amount_remaining, :string
    add_column :mollie_pay_payments, :amount_captured, :string, default: "0"
    add_column :mollie_pay_payments, :amount_charged_back, :string, default: "0"
  end
end
