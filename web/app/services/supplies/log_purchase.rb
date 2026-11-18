module Supplies
  # Saves a restock (from the Bought form, a scan, or a receipt line) and, when asked, a paid
  # Ledger expense for it, in one transaction.
  #
  # The stock counts from now, even when the purchase date is weeks back: "left before" is what is
  # there now, so the item has left before + bought from this moment. Slotted in at its purchase
  # date instead, the counts made since would cancel it and the difference would read as usage.
  # `dated_back` is for a purchase entered as history (Supplies::PurchaseDetails), which counts
  # from its purchase date
  class LogPurchase
    def self.call(supply, attributes, user:, add_to_ledger: false, dated_back: false)
      purchase = supply.purchases.new(attributes.merge(household: supply.household, created_by: user))
      purchase.currency ||= supply.household.default_currency
      purchase.stocked_at ||= Time.current unless dated_back
      purchase.left_before = supply.forecast.on_hand_rounded if purchase.left_before.nil?
      return purchase unless purchase.valid?

      SupplyPurchase.transaction do
        if add_to_ledger
          details = [ "#{supply.name} ×#{purchase.quantity}", purchase.store ].compact.join(" · ")
          purchase.record = LedgerRecord.call(supply.household, amount: purchase.total_price, paid_on: purchase.purchased_on,
                                              details:, currency: purchase.currency, user:)
        end
        purchase.save!
        StockChanged.call(supply)
      end
      purchase
    end
  end
end
