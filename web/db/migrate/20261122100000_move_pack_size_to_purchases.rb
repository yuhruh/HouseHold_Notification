# A pack size belongs to the brand bought, not the item: Pet snack can be Brand A in packs of 4 and
# Brand B in packs of 20. Each purchase and old price keeps its own; an item's size moves to all of them
class MovePackSizeToPurchases < ActiveRecord::Migration[8.1]
  TABLES = %i[supply_purchases supply_prices].freeze
  UNITS = "'piece', 'roll', 'bottle', 'can'".freeze

  def up
    TABLES.each do |table|
      add_column table, :pack_size, :integer
      add_column table, :pack_unit, :string
      add_check_constraint table, "pack_size IS NULL OR pack_size >= 2", name: "#{table}_pack_size"
      add_check_constraint table, "pack_unit IS NULL OR pack_unit IN (#{UNITS})", name: "#{table}_pack_unit"
      execute <<~SQL
        UPDATE #{table} SET pack_size = supplies.pack_size, pack_unit = supplies.pack_unit
        FROM supplies WHERE supplies.id = #{table}.supply_id AND supplies.pack_size IS NOT NULL
      SQL
    end
    remove_check_constraint :supplies, name: "supplies_pack_size"
    remove_check_constraint :supplies, name: "supplies_pack_unit"
    remove_column :supplies, :pack_size
    remove_column :supplies, :pack_unit
  end

  def down
    add_column :supplies, :pack_size, :integer
    add_column :supplies, :pack_unit, :string
    add_check_constraint :supplies, "pack_size IS NULL OR pack_size >= 2", name: "supplies_pack_size"
    add_check_constraint :supplies, "pack_unit IS NULL OR pack_unit IN (#{UNITS})", name: "supplies_pack_unit"
    execute <<~SQL
      UPDATE supplies SET pack_size = latest.pack_size, pack_unit = latest.pack_unit
      FROM (SELECT DISTINCT ON (supply_id) supply_id, pack_size, pack_unit FROM supply_purchases
            WHERE pack_size IS NOT NULL ORDER BY supply_id, purchased_on DESC, created_at DESC) latest
      WHERE supplies.id = latest.supply_id
    SQL
    TABLES.each do |table|
      remove_column table, :pack_size
      remove_column table, :pack_unit
    end
  end
end
