class CreateCustomers < ActiveRecord::Migration[7.2]
  def change
    create_table :customers do |t|
      t.string :name
      t.string :phone
      t.string :email
      t.string :customer_id
      t.integer :user_id

      t.timestamps
    end
  end
end
