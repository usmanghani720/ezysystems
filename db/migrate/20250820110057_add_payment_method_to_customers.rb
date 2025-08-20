class AddPaymentMethodToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :payment_method, :string
  end
end
