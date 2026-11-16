# Several brands in one supply item: a purchase keeps the product it was (the brand and size, for
# comparing prices), and a saved barcode keeps the product it belongs to, so the next scan fills it in
class AddProductNameToSupplyPurchasesAndBarcodes < ActiveRecord::Migration[8.1]
  def change
    add_column :supply_purchases, :product_name, :string
    add_column :supply_barcodes, :product_name, :string
  end
end
