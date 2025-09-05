class AddCustomerCardUrlToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :customer_card_url, :string
  end
end
