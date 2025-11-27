class AddLastPaymentColumnsToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :last_payment_id, :string
    add_column :customers, :last_payment_amount, :float
    add_column :customers, :last_payment_currency, :string
    add_column :customers, :last_payment_date, :string
  end
end
