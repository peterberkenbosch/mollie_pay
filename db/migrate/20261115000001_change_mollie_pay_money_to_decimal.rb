# Money is decimal(15,4): four decimals is what accounting software keeps, and
# fifteen significant digits is what SQLite holds exactly, since it stores a
# decimal as a REAL. See engine-family ADR 006. The amounts were text; SQLite
# converts the stored values when the table is rebuilt.
class ChangeMolliePayMoneyToDecimal < ActiveRecord::Migration[8.1]
  COLUMNS = {
    mollie_pay_subscriptions:  { amount: { null: false, default: 0 } },
    mollie_pay_refunds:        { amount: { null: false, default: 0 } },
    mollie_pay_chargebacks:    { amount: { null: false, default: 0 } },
    mollie_pay_sales_invoices: { amount: {} },
    mollie_pay_payments:       {
      amount:              { null: false, default: 0 },
      amount_refunded:     { default: 0 },
      amount_captured:     { default: 0 },
      amount_charged_back: { default: 0 },
      amount_remaining:    {}
    }
  }.freeze

  def up
    each_column do |table, column, options|
      change_column table, column, :decimal, precision: 15, scale: 4, **options
    end
  end

  def down
    each_column do |table, column, options|
      change_column table, column, :string, **options.merge(options.key?(:default) ? { default: "0" } : {})
    end
  end

  private
    def each_column
      COLUMNS.each do |table, columns|
        columns.each { |column, options| yield table, column, options }
      end
    end
end
