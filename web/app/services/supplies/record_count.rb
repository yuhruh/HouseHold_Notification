module Supplies
  # −1 ("used one", from the last known count, so taps never double-count the estimated usage in
  # between) or "I have N left" (a count you just made)
  class RecordCount
    def self.used_one(supply, user:)
      call(supply, [ supply.level - 1, 0 ].max, user:)
    end

    def self.call(supply, level, user:)
      count = supply.counts.new(level:, created_by: user)
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
