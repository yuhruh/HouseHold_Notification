# A count of what's left: a −1 tap or "I have N left". Each one is an observation the forecast
# learns from; Undo deletes it. On an item with several brands in stock it can also say which brand
# the −1 was (used_product, "" for the stock with no brand named) or give each brand's number
# (by_product, product => how many); Supplies::Brands reads both. A −1 on one batch (one purchase of
# a brand, with its own expiry date) also names that purchase (used_purchase).
class SupplyCount < ApplicationRecord
  belongs_to :supply
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :used_purchase, class_name: "SupplyPurchase", optional: true

  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }
  validates :used_product, length: { maximum: Priced::PRODUCT_NAME_MAX }
  validate :whole_numbers_by_product

  before_validation { self.counted_at ||= Time.current }

  def at = counted_at

  private

  def whole_numbers_by_product
    return if by_product.nil?
    valid = by_product.is_a?(Hash) && by_product.all? { |name, left| name.is_a?(String) && left.is_a?(Integer) && left.between?(0, 99_999) }
    errors.add(:level, :not_a_number) unless valid
  end
end
