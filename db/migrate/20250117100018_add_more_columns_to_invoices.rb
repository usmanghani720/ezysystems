class AddMoreColumnsToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :city, :string
    add_column :invoices, :state, :string
    add_column :invoices, :country, :string
    add_column :invoices, :line1, :string
    add_column :invoices, :line2, :string
    add_column :invoices, :postal_code, :string
    add_column :invoices, :phone, :string
  end
end
