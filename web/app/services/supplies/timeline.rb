module Supplies
  # A supply's purchases and counts in time order, each with the count it left behind: a count sets
  # it, a purchase adds what was bought to what was left before it. The forecast learns from it.
  class Timeline
    Event = Data.define(:at, :kind, :observed, :added, :level_after)

    def initialize(supply)
      @supply = supply
    end

    def events
      @events ||= begin
        purchases = @supply.purchases.reject(&:new_record?).map do |purchase|
          Event.new(at: purchase.at, kind: :purchase, observed: purchase.left_before, added: purchase.quantity,
                    level_after: purchase.left_before + purchase.quantity)
        end
        counts = @supply.counts.reject(&:new_record?).map do |count|
          Event.new(at: count.at, kind: :count, observed: count.level, added: 0, level_after: count.level)
        end
        (purchases + counts).sort_by(&:at)
      end
    end
  end
end
