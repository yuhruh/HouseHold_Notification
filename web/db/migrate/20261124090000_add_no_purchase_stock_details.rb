# Stock counted before any purchase was logged has no purchase behind it. Its own −1 says so
# (used_no_purchase), and "Add details" can save the purchase it came from without a price, when
# you can't find what you paid
class AddNoPurchaseStockDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :supply_counts, :used_no_purchase, :boolean, null: false, default: false
    change_column_null :supply_purchases, :total_price, true
  end
end
