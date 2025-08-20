class AddColumnsToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :user_id, :integer
    add_column :invoices, :status, :string
  end
end
