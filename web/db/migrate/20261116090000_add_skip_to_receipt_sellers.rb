# "Not a supplies store": a receipt from this seller (a restaurant, say) starts out of the import
class AddSkipToReceiptSellers < ActiveRecord::Migration[8.1]
  def change
    add_column :receipt_sellers, :skip, :boolean, null: false, default: false
  end
end
