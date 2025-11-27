class AddCardFieldsToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :last4, :string
    add_column :customers, :brand, :string
  end
end
