class AddNoteToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :note, :string
  end
end
