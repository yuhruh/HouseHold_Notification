# The star on a supply: a favorite of the whole household, listed on Supplies › Favorites
class AddFavoriteToSupplies < ActiveRecord::Migration[8.1]
  def change
    add_column :supplies, :favorite, :boolean, null: false, default: false
  end
end
