class AddColumnsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :transfer, :boolean
    add_column :users, :payout, :boolean
    add_column :users, :charges, :boolean
  end
end
