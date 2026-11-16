# An old price: what an item cost before, kept only for comparing prices (Price history, Where to
# buy). Unlike a purchase it never changes the count, the forecast, total spent or the Ledger.
class CreateSupplyPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :supply_prices do |t|
      t.references :household, null: false, foreign_key: true
      t.references :supply, null: false, foreign_key: true
      t.string :product_name
      t.string :store
      t.integer :quantity, null: false
      t.decimal :total_price, precision: 12, scale: 2, null: false
      t.string :currency, null: false, default: "TWD"
      t.date :purchased_on, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_check_constraint :supply_prices, "quantity > 0", name: "supply_prices_quantity_positive"
    add_check_constraint :supply_prices, "total_price >= 0", name: "supply_prices_total_not_negative"
  end
end
