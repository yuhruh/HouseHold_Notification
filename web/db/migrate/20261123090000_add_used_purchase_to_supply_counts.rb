# −1 on one batch: which purchase the unit came from, so a restock of the same brand with another
# expiry date keeps its own number (Supplies::Brands). Gone with the purchase: the −1 then counts as
# one of its brand, or of the stock to use first
class AddUsedPurchaseToSupplyCounts < ActiveRecord::Migration[8.1]
  def change
    add_reference :supply_counts, :used_purchase, foreign_key: { to_table: :supply_purchases, on_delete: :nullify }, null: true
  end
end
