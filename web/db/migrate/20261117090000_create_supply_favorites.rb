# Each owner and co-owner has their own star on a supply (shown in their colour), so Favorites can say
# whose star an item has. The stars so far were the household's, with no name on them: they become
# its owner's
class CreateSupplyFavorites < ActiveRecord::Migration[8.1]
  def up
    create_table :supply_favorites do |t|
      t.references :supply, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
      t.index %i[supply_id user_id], unique: true
    end
    execute <<~SQL
      INSERT INTO supply_favorites (supply_id, user_id, created_at)
      SELECT supplies.id, memberships.user_id, CURRENT_TIMESTAMP
      FROM supplies JOIN memberships ON memberships.household_id = supplies.household_id AND memberships.role = 'owner'
      WHERE supplies.favorite
    SQL
    remove_column :supplies, :favorite
  end

  def down
    add_column :supplies, :favorite, :boolean, null: false, default: false
    execute "UPDATE supplies SET favorite = TRUE WHERE id IN (SELECT supply_id FROM supply_favorites)"
    drop_table :supply_favorites
  end
end
