class AddStripeEmailToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :stripe_email, :string
  end
end
