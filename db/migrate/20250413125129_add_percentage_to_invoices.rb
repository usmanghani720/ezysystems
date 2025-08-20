class AddPercentageToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :percentage, :float
  end
end
