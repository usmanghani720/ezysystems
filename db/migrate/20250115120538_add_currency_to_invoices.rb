class AddCurrencyToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :currency, :string
  end
end
