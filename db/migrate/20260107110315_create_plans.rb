class CreatePlans < ActiveRecord::Migration[7.2]
  def change
    create_table :plans do |t|
      t.string  :name, null: false
      t.float :amount_cents, null: false
      t.string  :currency, null: false, default: "usd"

      t.string  :stripe_product_id, null: false
      t.string  :stripe_price_id, null: false

      t.timestamps
    end

    add_index :plans, [:amount_cents, :currency], unique: true
    add_index :plans, :stripe_price_id, unique: true
    
  end
end
