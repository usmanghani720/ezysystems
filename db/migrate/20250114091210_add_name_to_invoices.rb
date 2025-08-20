class AddNameToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :name, :string
  end
end
