# A count saved by −1 says so, so History reads "Used 1 · 23 bottles left" for every −1, not only one
# that named a brand. A −1 that named a brand (used_product) was always one; an older −1 on an item
# with one brand can't be told from a typed count, so it keeps reading "Counted"
class AddUsedOneToSupplyCounts < ActiveRecord::Migration[8.1]
  def up
    add_column :supply_counts, :used_one, :boolean, default: false, null: false
    execute "UPDATE supply_counts SET used_one = TRUE WHERE used_product IS NOT NULL"
  end

  def down
    remove_column :supply_counts, :used_one
  end
end
