class CreatePayouts < ActiveRecord::Migration[7.2]
  def change
    create_table :payouts do |t|
      t.float :amount
      t.integer :user_id

      t.timestamps
    end
  end
end
