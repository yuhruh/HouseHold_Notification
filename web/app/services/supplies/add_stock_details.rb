module Supplies
  # "Add details" for the stock counted before any purchase was logged (Brands#no_purchase_batch):
  # the purchase it came from, bought on or before the day it was first counted
  # (Brands#no_purchase_counted). Either an old price from Price history, dated on or before that day
  # (#choices: it becomes that purchase, so it is listed once), or the details typed in, the price
  # optional when you can't find what you paid.
  #
  # Saved just before that count with nothing left before it, like a first purchase added on Edit
  # item (PurchaseDetails.first_purchase): the count becomes a usage reading, the stock becomes that
  # purchase's batch with its expiry date, and the −1s already taken from it name it.
  class AddStockDetails
    def initialize(supply)
      @supply = supply
      @household = supply.household
    end

    # The stock with no purchase, while some is left (nil once it has its purchase)
    def batch = @batch ||= @supply.brands.no_purchase_batch

    def counted = @counted ||= @supply.brands.no_purchase_counted

    # The day it was first counted: the purchase was on or before it
    def last_day
      zone = ActiveSupport::TimeZone[@household.time_zone] || Time.zone
      counted.at.in_time_zone(zone).to_date
    end

    # How many there were then: it was bought at least that many
    def counted_left = counted.is_a?(SupplyPurchase) ? counted.left_before : counted.level

    # Old prices of this item on or before that day, newest first
    def choices = @choices ||= @supply.prices.select { it.purchased_on <= last_day }.sort_by { [ -it.purchased_on.jd, -it.created_at.to_f ] }

    # An old price becomes the purchase, with how many were bought and the expiry date given
    def from_price(price, quantity:, expires_on:, user:, add_to_ledger:)
      attributes = price.attributes.symbolize_keys.slice(*%i[product_name store total_price currency purchased_on paid_currency paid_total exchange_rate
                                                             paid_by card_fee_percent card_fee_included pack_size pack_unit])
      save(attributes.merge(quantity:, expires_on:), user:, add_to_ledger:, price:)
    end

    # The details typed in; an empty price box leaves the price out (and its currency with it)
    def entered(attributes, user:, add_to_ledger:)
      attributes = attributes.to_h.symbolize_keys
      attributes = attributes.except(*PaidAmount::KEYS) if attributes[:total_price].blank?
      save(PaidAmount.resolve(attributes, household: @household), user:, add_to_ledger:)
    end

    private

    def save(attributes, user:, add_to_ledger:, price: nil)
      purchase = @supply.purchases.new(attributes.merge(household: @household, created_by: user, left_before: 0, created_at: counted.at - 1.second,
                                                        price_optional: true))
      purchase.currency ||= @household.default_currency
      return purchase unless valid?(purchase)

      SupplyPurchase.transaction do
        if add_to_ledger && purchase.priced?
          details = [ "#{@supply.name} ×#{purchase.quantity}", purchase.store ].compact.join(" · ")
          purchase.record = LedgerRecord.call(@household, amount: purchase.total_price, paid_on: purchase.purchased_on, details:,
                                              currency: purchase.currency, user:)
        end
        purchase.save!
        price&.destroy!
        @supply.counts.where(used_no_purchase: true).update_all(used_no_purchase: false, used_purchase_id: purchase.id,
                                                                used_product: Brands.key(purchase.product_name))
        StockChanged.call(@supply)
      end
      purchase
    end

    # Bought on or before the day those were counted, and at least as many as were counted then
    def valid?(purchase)
      purchase.validate
      if purchase.purchased_on && purchase.purchased_on > last_day
        purchase.errors.add(:purchased_on, :after_count, date: I18n.l(last_day, format: :long))
      end
      if purchase.quantity.is_a?(Integer) && purchase.quantity.positive? && purchase.quantity < counted_left
        purchase.errors.add(:quantity, :fewer_than_counted, count: counted_left, date: I18n.l(last_day, format: :long))
      end
      purchase.errors.empty?
    end
  end
end
