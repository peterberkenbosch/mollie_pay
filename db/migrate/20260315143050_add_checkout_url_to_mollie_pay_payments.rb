class AddCheckoutUrlToMolliePayPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :mollie_pay_payments, :checkout_url, :string
  end
end
