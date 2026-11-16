# A product barcode (EAN-13/JAN, EAN-8, UPC) this household has saved on one of its supplies, so the
# next scan goes straight to that item. One item can have several (different brands or sizes), each
# with the product's name, which the next scan fills in on the purchase.
class SupplyBarcode < ApplicationRecord
  belongs_to :household
  belongs_to :supply

  normalizes :code, with: ->(code) { code.to_s.gsub(/\D/, "") }
  normalizes :product_name, with: ->(name) { name.to_s.squish.presence }

  validates :product_name, length: { maximum: Priced::PRODUCT_NAME_MAX }
  validates :code, format: { with: /\A\d{8,14}\z/ }, uniqueness: { scope: :household_id }

  # A scanned code is saved on the item it was bought as: new to the household, or moved over from an
  # archived item (a duplicate put away). One this item already has gets the product's name when it
  # had none. A code on another item still in use stays where it is.
  def self.remember(supply, code, product_name: nil)
    barcode = supply.household.supply_barcodes.includes(:supply).find_by(code: code.to_s.gsub(/\D/, ""))
    if barcode.nil?
      supply.barcodes.create(household: supply.household, code:, product_name:)
    elsif barcode.supply_id == supply.id
      barcode.update(product_name:) if barcode.product_name.blank? && product_name.present?
    elsif barcode.supply.archived_at
      barcode.update(supply:, product_name: product_name.presence || barcode.product_name)
    end
  end

  # Whether a scanned code can still be given to an item: nobody's yet, or an archived item's
  def self.free?(household, code)
    barcode = household.supply_barcodes.includes(:supply).find_by(code:)
    barcode.nil? || barcode.supply.archived_at.present?
  end
end
