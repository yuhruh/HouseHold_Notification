# One restock: how many, what it cost in total, where, which product it was (an item can be several
# brands; they share its count and forecast) and (optionally) when it expires.
# left_before is the count just before it, which is how the forecast learns the usage rate.
# The price per unit is worked out from the total, never typed in.
class SupplyPurchase < ApplicationRecord
  include Priced

  belongs_to :household
  belongs_to :supply
  belongs_to :record, optional: true
  belongs_to :receipt_import, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :left_before, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }

  # Set by "Add details" (Supplies::AddStockDetails): the price may be left empty
  attr_writer :price_optional

  def old_price? = false

  # Saved with no price, it may stay without one when corrected on Edit item
  def price_optional? = @price_optional || (persisted? && total_price_in_database.nil?)

  # When its stock joined the count, for ordering against counts. A restock counts from the moment
  # it was logged (stocked_at), whatever its purchase date: what was left before it was answered
  # then, and counts made since the purchase date didn't include it. A purchase entered as history
  # (Supplies::PurchaseDetails) has no stocked_at and counts from its purchase date: the moment it
  # was logged when it was logged the same day, else midday of that date in the household's zone
  def at
    return stocked_at if stocked_at

    zone = ActiveSupport::TimeZone[household.time_zone] || Time.zone
    logged = (created_at || Time.current).in_time_zone(zone)
    logged.to_date == purchased_on ? logged : zone.local(purchased_on.year, purchased_on.month, purchased_on.day, 12)
  end
end
