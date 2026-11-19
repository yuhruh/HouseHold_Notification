# What a purchase and an old price share: how many, the total, the store and the day, with the
# price per unit worked out from the total, and the product it was (the brand or pack, when it
# differs from the item's name: one item can be several brands)
module Priced
  extend ActiveSupport::Concern

  MAX_TOTAL = BigDecimal("10000000000")
  PRODUCT_NAME_MAX = 80

  included do
    normalizes :store, with: ->(store) { store.to_s.squish.presence }
    normalizes :product_name, with: ->(name) { name.to_s.squish.presence }

    # The item's own name isn't a product name: it would go stale when the item is renamed
    before_validation { self.product_name = nil if product_name && product_name == supply&.name }

    # The two home-currency boxes of a price typed in another currency (Supplies::PaidAmount), kept
    # only so the form shows them again when it is refused
    attr_accessor :home_total, :home_total_with_fee

    validates :product_name, length: { maximum: PRODUCT_NAME_MAX }
    validates :purchased_on, presence: true
    validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }
    validates :total_price, numericality: { greater_than_or_equal_to: 0, less_than: MAX_TOTAL }, unless: :home_amount_missing?
    validates :currency, inclusion: { in: Household::CURRENCIES }
    validates :store, length: { maximum: 60 }
    validates :paid_currency, inclusion: { in: Supplies::Currency::CODES }, allow_nil: true
    validates :paid_total, numericality: { greater_than: 0, less_than: MAX_TOTAL }, if: :paid_abroad?
    validates :paid_by, inclusion: { in: Supplies::PaidAmount::PAID_BY }, allow_nil: true
    validates :card_fee_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: Supplies::PaidAmount::MAX_CARD_FEE }, allow_nil: true
    validate :whole_amount_for_whole_currency
    validate :home_amount_given
    validate :not_in_the_future
  end

  def unit_price = total_price / quantity

  def display_name = product_name || supply.name

  # Bought in another currency: paid_total in paid_currency, and total_price is what that came to
  def paid_abroad? = paid_currency.present?

  private

  # A price in another currency with no rate to be had and no amount typed: one clear message
  # asking for the amount, instead of "Total price is not a number"
  def home_amount_missing? = paid_abroad? && total_price.nil?

  def home_amount_given
    return unless home_amount_missing? && Supplies::Currency.known?(paid_currency)
    errors.add(:base, :home_amount_missing, paid: paid_currency, symbol: Supplies::Currency[currency]&.symbol || currency)
  end

  def not_in_the_future
    errors.add(:purchased_on, :in_the_future) if purchased_on && household && purchased_on > household.today
  end

  # NT$ has no cents; neither does a price in yen, won or dong. Abroad, total_price is the box
  # "Amount in NT$" and the price box is paid_total
  def whole_amount_for_whole_currency
    if total_price && Household::WHOLE_CURRENCIES.include?(currency) && total_price != total_price.round
      errors.add(paid_abroad? ? :home_total : :total_price, :whole_number)
    end
    if paid_total && Supplies::Currency[paid_currency]&.whole? && paid_total != paid_total.round
      errors.add(:paid_total, :whole_number)
    end
  end
end
