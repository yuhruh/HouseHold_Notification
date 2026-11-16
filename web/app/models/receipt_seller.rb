# The store name a household gave a seller's tax ID (統編) on a receipt, asked once, and whether it's
# "not a supplies store" (its receipts start out of an import)
class ReceiptSeller < ApplicationRecord
  belongs_to :household

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :tax_id, presence: true, uniqueness: { scope: :household_id }
  validates :name, presence: true, length: { maximum: 60 }
end
