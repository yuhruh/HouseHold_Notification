module Supplies
  # After a purchase or count is added or removed: the last known count follows the newest event,
  # the cached usage rate is recomputed, and an alert already sent is cleared once the item no
  # longer needs buying, so the next run-out alerts again
  class StockChanged
    def self.call(supply)
      supply.reload
      event = Timeline.new(supply).events.last
      supply.assign_attributes(level: event.level_after, level_at: event.at) if event
      forecast = supply.forecast
      supply.usage_per_day = forecast.rate&.round(4)
      if supply.alert_state != "ok" && !forecast.needs_buying?
        supply.alert_state = "ok"
        supply.alerted_at = nil
      end
      supply.save!
      supply
    end
  end
end
