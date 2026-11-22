# An item counted in packs, boxes or bags can say what's in each one ("4 pieces"), so prices show
# per piece too. One size per item; null for everything else
class AddPackSizeToSupplies < ActiveRecord::Migration[8.1]
  def change
    add_column :supplies, :pack_size, :integer
    add_column :supplies, :pack_unit, :string
    add_check_constraint :supplies, "pack_size IS NULL OR pack_size >= 2", name: "supplies_pack_size"
    add_check_constraint :supplies, "pack_unit IS NULL OR pack_unit IN ('piece', 'roll', 'bottle', 'can')", name: "supplies_pack_unit"
  end
end
