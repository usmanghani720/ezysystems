class CreateInvoices < ActiveRecord::Migration[7.2]
  def change
    create_table :invoices do |t|
      t.string :account_id
      t.string :unique_id
      t.string :invoice_url
      t.string :description
      t.float :amount
      t.string :email

      t.timestamps
    end
  end
end
