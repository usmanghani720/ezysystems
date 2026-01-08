class AddCardColumnsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :payment_method, :string
    add_column :users, :last4, :string
    add_column :users, :brand, :string
    add_column :users, :vendor_id, :string
  end
end
