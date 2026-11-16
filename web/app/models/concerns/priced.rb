# What a purchase and an old price share: how many, the total, the store and the day, with the
# price per unit worked out from the total
module Priced
  extend ActiveSupport::Concern

  MAX_TOTAL = BigDecimal("10000000000")

  included do
    normalizes :store, with: ->(store) { store.to_s.squish.presence }

    validates :purchased_on, presence: true
    validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }
    validates :total_price, numericality: { greater_than_or_equal_to: 0, less_than: MAX_TOTAL }
    validates :currency, inclusion: { in: Household::CURRENCIES }
    validates :store, length: { maximum: 60 }
    validate :whole_amount_for_whole_currency
    validate :not_in_the_future
  end

  def unit_price = total_price / quantity

  private

  def not_in_the_future
    errors.add(:purchased_on, :in_the_future) if purchased_on && household && purchased_on > household.today
  end

  def whole_amount_for_whole_currency
    return unless total_price && Household::WHOLE_CURRENCIES.include?(currency)
    errors.add(:total_price, :whole_number) unless total_price == total_price.round
  end
end
