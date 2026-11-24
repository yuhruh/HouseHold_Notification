# What a purchase and an old price share: how many, the total, the store and the day, with the
# price per unit worked out from the total, and the product it was (the brand or pack, when it
# differs from the item's name: one item can be several brands). Counted in packs, boxes or bags, it
# can also say what was in each ("Each pack has 4 pieces"), for the price per piece: each brand keeps
# its own size, so it's on the purchase, not the item
module Priced
  extend ActiveSupport::Concern

  MAX_TOTAL = BigDecimal("10000000000")
  PRODUCT_NAME_MAX = 80

  included do
    normalizes :store, with: ->(store) { store.to_s.squish.presence }
    normalizes :product_name, with: ->(name) { name.to_s.squish.presence }

    # The item's own name isn't a product name: it would go stale when the item is renamed
    before_validation { self.product_name = nil if product_name && product_name == supply&.name }
    # Given a size, what's inside is pieces unless said otherwise; with none, nothing is inside
    before_validation { pack_size.present? ? self.pack_unit = pack_unit.presence || "piece" : self.pack_unit = nil }

    # The two home-currency boxes of a price typed in another currency (Supplies::PaidAmount), kept
    # only so the form shows them again when it is refused
    attr_accessor :home_total, :home_total_with_fee

    validates :product_name, length: { maximum: PRODUCT_NAME_MAX }
    validates :pack_size, numericality: { only_integer: true, in: 2..999 }, allow_nil: true
    validates :pack_unit, inclusion: { in: Supply::PACK_UNITS }, allow_nil: true
    validates :purchased_on, presence: true
    validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }
    validates :total_price, numericality: { greater_than_or_equal_to: 0, less_than: MAX_TOTAL }, unless: -> { home_amount_missing? || (total_price.nil? && price_optional?) }
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

  # A purchase saved by "Add details" may have no price (you couldn't find what you paid): it is left
  # out of Price history, Where to buy and what was spent
  def priced? = !total_price.nil?

  def price_optional? = false

  def unit_price = total_price / quantity

  def display_name = product_name || supply.name

  # A size only counts while the item is counted in packs, boxes or bags: switched to pieces it is
  # set aside, not lost, and switching back brings it back
  def packed? = pack_size.present? && supply.in_packs?

  def piece_price = unit_price / pack_size

  # A new one of a brand bought before in packs: the size it came in then (Supply#pack_size_for).
  # True when there was one
  def fill_pack_size
    size, inner = supply.pack_size_for(product_name)
    self.pack_size, self.pack_unit = size, inner if size
    size.present?
  end

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
