# Which brand a −1 took a bottle from, and the per-brand numbers of a count made brand by brand
# (Supplies::Brands). Both empty for a plain count: the oldest stock is taken first
class AddBrandsToSupplyCounts < ActiveRecord::Migration[8.1]
  def change
    add_column :supply_counts, :used_product, :string
    add_column :supply_counts, :by_product, :jsonb
  end
end
