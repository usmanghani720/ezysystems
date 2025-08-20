class AddAccountTypeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :account_type, :string
  end
end
