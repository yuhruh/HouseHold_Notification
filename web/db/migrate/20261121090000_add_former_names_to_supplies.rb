# The names of items combined into this one (Supplies::Combine), so a receipt line with one of them
# is still matched to this item even when nothing else (a purchase, an old price, a barcode) carries it
class AddFormerNamesToSupplies < ActiveRecord::Migration[8.1]
  def change
    add_column :supplies, :former_names, :string, array: true, default: [], null: false
  end
end
