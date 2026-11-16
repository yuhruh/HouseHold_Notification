# One restock: how many, what it cost in total, where, and (optionally) when it expires.
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

  def old_price? = false
  def display_name = supply.name

  # When it happened, for ordering against counts: the moment it was logged when it was logged the
  # same day, else midday of the purchase date in the household's zone
  def at
    zone = ActiveSupport::TimeZone[household.time_zone] || Time.zone
    logged = (created_at || Time.current).in_time_zone(zone)
    logged.to_date == purchased_on ? logged : zone.local(purchased_on.year, purchased_on.month, purchased_on.day, 12)
  end
end
