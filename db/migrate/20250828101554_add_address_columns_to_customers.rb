class AddAddressColumnsToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :line1, :string
    add_column :customers, :line2, :string
    add_column :customers, :city, :string
    add_column :customers, :state, :string
    add_column :customers, :postal_code, :string
    add_column :customers, :country, :string
  end
end
