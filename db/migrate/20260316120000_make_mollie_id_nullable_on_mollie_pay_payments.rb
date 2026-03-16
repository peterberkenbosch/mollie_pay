class MakeMollieIdNullableOnMolliePayPayments < ActiveRecord::Migration[8.1]
  def change
    change_column_null :mollie_pay_payments, :mollie_id, true
  end
end
