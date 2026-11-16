module Supplies
  # The purchase on the New item and Edit forms.
  #
  # New item, already bought (maybe a while ago, some used since): the purchase is saved with nothing
  # left before it, then what's left now as a count, so bought 12 on Nov 1 and 5 left today is a
  # usage reading straight away (7 in N days) and the forecast has a rate from day one.
  #
  # Edit: corrects the latest purchase (its price, store, date, quantity or expiry, and the Ledger
  # expense linked to it), or, when there is none yet, adds the purchase the item started from.
  class PurchaseDetails
    FIELDS = %i[purchased_on quantity total_price store expires_on product_name].freeze

    # The person filled in a purchase (the date alone, prefilled with today, doesn't count)
    def self.given?(attributes) = attributes.values_at(:quantity, :total_price).any?(&:present?)

    def self.for_new(supply, attributes, level:, user:, add_to_ledger:)
      purchase = LogPurchase.call(supply, attributes.merge(left_before: 0), user:, add_to_ledger:)
      return purchase unless purchase.persisted?

      # What's left now; on the day of purchase, only when some are already used
      RecordCount.call(supply, level, user:) if purchase.purchased_on < supply.household.today || level != purchase.quantity
      purchase
    end

    def self.for_edit(supply, attributes, user:, add_to_ledger:)
      purchase = supply.latest_purchase
      return first_purchase(supply, attributes, user:, add_to_ledger:) unless purchase

      purchase.assign_attributes(attributes)
      return purchase unless purchase.valid?

      SupplyPurchase.transaction do
        purchase.save!
        sync_ledger(purchase, add_to_ledger:, user:)
        StockChanged.call(supply)
      end
      purchase
    end

    # Added after the fact: it goes before the item's first count when bought on or before that day,
    # with nothing left before it, so the count becomes a usage reading
    def self.first_purchase(supply, attributes, user:, add_to_ledger:)
      first = supply.counts.min_by(&:at)
      zone = ActiveSupport::TimeZone[supply.household.time_zone] || Time.zone
      bought_on = attributes[:purchased_on].presence && Date.parse(attributes[:purchased_on].to_s)
      before_first = first && bought_on && bought_on <= first.at.in_time_zone(zone).to_date
      attributes = attributes.merge(left_before: 0, created_at: first.at - 1.second) if before_first
      LogPurchase.call(supply, attributes, user:, add_to_ledger:)
    rescue Date::Error
      supply.purchases.new(attributes.merge(household: supply.household, purchased_on: nil)).tap(&:validate)
    end

    # The Ledger expense follows the purchase's new total and date; "Also add to Ledger" adds one
    def self.sync_ledger(purchase, add_to_ledger:, user:)
      if (record = purchase.record)
        record.update!(amount_required: purchase.total_price, amount_paid: purchase.total_price, paid_on: purchase.purchased_on)
        RecordEvent.log!(record, :updated, user:) if record.saved_changes?
      elsif add_to_ledger
        supply = purchase.supply
        details = [ "#{supply.name} ×#{purchase.quantity}", purchase.store ].compact.join(" · ")
        purchase.update!(record: LedgerRecord.call(supply.household, amount: purchase.total_price, paid_on: purchase.purchased_on,
                                                   details:, currency: purchase.currency, user:))
      end
    end
  end
end
