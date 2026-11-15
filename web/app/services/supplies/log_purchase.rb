module Supplies
  # Saves a restock (from the Bought form, a scan, or a receipt line) and, when asked, a paid
  # Ledger expense for it, in one transaction
  class LogPurchase
    def self.call(supply, attributes, user:, add_to_ledger: false)
      purchase = supply.purchases.new(attributes.merge(household: supply.household, created_by: user))
      purchase.currency ||= supply.household.default_currency
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
