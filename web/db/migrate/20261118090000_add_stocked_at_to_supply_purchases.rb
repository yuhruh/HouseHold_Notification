# When a restock joined the item's count: the moment it was logged, whatever its purchase date.
# "How many were left before this?" is answered about now, so a restock dated weeks back must not be
# slotted in before the counts made since (they would cancel it and read as usage).
# Empty for a purchase entered as history (a new item's "I already bought these", Edit's first
# purchase) and for purchases from before this column: those count from their purchase date
class AddStockedAtToSupplyPurchases < ActiveRecord::Migration[8.1]
  def change
    add_column :supply_purchases, :stocked_at, :datetime
  end
end
