class AddTaxColumnsToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :tax_type, :string
    add_column :invoices, :tax_value, :string
  end
end
