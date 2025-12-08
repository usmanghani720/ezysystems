class AddRequire3dsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :require_3ds, :boolean, null: false, default: false
  end
end
