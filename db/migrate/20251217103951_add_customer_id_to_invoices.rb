class AddCustomerIdToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :customer_id, :string
  end
end
