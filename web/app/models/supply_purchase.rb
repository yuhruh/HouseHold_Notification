# One restock: how many, what it cost in total, where, and (optionally) when it expires.
# left_before is the count just before it, which is how the forecast learns the usage rate.
# The price per unit is worked out from the total, never typed in.
class SupplyPurchase < ApplicationRecord
  MAX_TOTAL = BigDecimal("10000000000")

  belongs_to :household
  belongs_to :supply
  belongs_to :record, optional: true
  belongs_to :receipt_import, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  normalizes :store, with: ->(store) { store.to_s.squish.presence }

  validates :purchased_on, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }
  validates :left_before, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0, less_than: MAX_TOTAL }
  validates :currency, inclusion: { in: Household::CURRENCIES }
  validates :store, length: { maximum: 60 }
  validate :whole_amount_for_whole_currency
  validate :not_in_the_future

  def unit_price = total_price / quantity

  # When it happened, for ordering against counts: the moment it was logged when it was logged the
  # same day, else midday of the purchase date in the household's zone
  def at
    zone = ActiveSupport::TimeZone[household.time_zone] || Time.zone
    logged = (created_at || Time.current).in_time_zone(zone)
    logged.to_date == purchased_on ? logged : zone.local(purchased_on.year, purchased_on.month, purchased_on.day, 12)
  end

  private

  def not_in_the_future
    errors.add(:purchased_on, :in_the_future) if purchased_on && household && purchased_on > household.today
  end

  def whole_amount_for_whole_currency
    return unless total_price && Household::WHOLE_CURRENCIES.include?(currency)
    errors.add(:total_price, :whole_number) unless total_price == total_price.round
  end
end
