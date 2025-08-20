class CreateIntents < ActiveRecord::Migration[7.2]
  def change
    create_table :intents do |t|
      t.integer :invoice_id
      t.string :payment_intent_id

      t.timestamps
    end
  end
end
