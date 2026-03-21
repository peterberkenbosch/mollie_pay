class AddAuthorizedAtToMolliePayPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :mollie_pay_payments, :authorized_at, :datetime
  end
end
