module Supplies
  # −1 ("used one", from the last known count, so taps never double-count the estimated usage in
  # between) or "I have N left" (a count you just made). With several brands in stock, −1 names the
  # brand the bottle was (and, on one batch's line, the purchase it was from), and a count gives each
  # brand's number (the count is their sum)
  class RecordCount
    # `no_purchase`: from the stock with no purchase behind it (Supplies::Brands::NO_PURCHASE)
    def self.used_one(supply, user:, product: nil, purchase: nil, no_purchase: false)
      call(supply, [ supply.level - 1, 0 ].max, user:, used_product: product, used_purchase: purchase, used_no_purchase: no_purchase)
    end

    def self.by_brand(supply, numbers, user:)
      call(supply, numbers.values.sum, user:, by_product: numbers)
    end

    def self.call(supply, level, user:, used_product: nil, by_product: nil, used_purchase: nil, used_no_purchase: false)
      count = supply.counts.new(level:, created_by: user, used_product:, by_product:, used_purchase:, used_no_purchase:)
      return count unless count.valid?

      SupplyCount.transaction do
        count.save!
        StockChanged.call(supply)
      end
      count
    end

    def self.undo(count)
      supply = count.supply
      SupplyCount.transaction do
        count.destroy!
        StockChanged.call(supply)
      end
    end
  end
end
