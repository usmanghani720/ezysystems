class AddPaymentIntentIdToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :payment_intent_id, :string
  end
end
