# A product barcode (EAN-13/JAN, EAN-8, UPC) this household has saved on one of its supplies, so the
# next scan goes straight to that item. One item can have several (different brands or sizes).
class SupplyBarcode < ApplicationRecord
  belongs_to :household
  belongs_to :supply

  normalizes :code, with: ->(code) { code.to_s.gsub(/\D/, "") }

  validates :code, format: { with: /\A\d{8,14}\z/ }, uniqueness: { scope: :household_id }
end
