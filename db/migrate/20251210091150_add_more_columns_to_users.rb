class AddMoreColumnsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :unique_code, :string
    add_column :users, :referral_id, :integer
  end
end
