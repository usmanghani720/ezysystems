class AddMonthlyChargedToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :monthly_charged, :boolean
  end
end
