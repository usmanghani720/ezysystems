# db/migrate/20260115000000_create_connected_transactions.rb
class CreateConnectedTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :connected_transactions do |t|
      t.string  :stripe_account_id, null: false
      t.string  :payment_intent_id, null: false
      t.string  :charge_id

      t.integer :amount
      t.string  :currency
      t.string  :status

      t.string  :customer_email
      t.string  :payment_method_label

      t.integer :amount_refunded, default: 0, null: false
      t.boolean :refunded, default: false, null: false

      t.integer :created_at_stripe, null: false

      t.timestamps
    end

    add_index :connected_transactions, :payment_intent_id, unique: true
    add_index :connected_transactions, [:stripe_account_id, :created_at_stripe]
    add_index :connected_transactions, :created_at_stripe
    add_index :connected_transactions, :charge_id
  end
end
