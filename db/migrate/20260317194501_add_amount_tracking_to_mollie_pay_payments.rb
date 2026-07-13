class AddAmountTrackingToMolliePayPayments < ActiveRecord::Migration[8.0]
  def change
    # BigDecimal money as text (see MolliePay::DecimalMoneyType)
    add_column :mollie_pay_payments, :amount_refunded, :string, default: "0"
    add_column :mollie_pay_payments, :amount_remaining, :string
    add_column :mollie_pay_payments, :amount_captured, :string, default: "0"
    add_column :mollie_pay_payments, :amount_charged_back, :string, default: "0"
  end
end
