# An old price: what an item cost at a store on a day, for comparing prices only. It shows in Price
# history and counts in Where to buy, but never changes the count, the forecast, total spent or the
# Ledger (that's what a SupplyPurchase is for).
class SupplyPrice < ApplicationRecord
  include Priced

  belongs_to :household
  belongs_to :supply
  belongs_to :created_by, class_name: "User", optional: true

  normalizes :product_name, with: ->(name) { name.to_s.squish.presence }

  validates :product_name, length: { maximum: 80 }

  def old_price? = true
  def display_name = product_name || supply.name
end
