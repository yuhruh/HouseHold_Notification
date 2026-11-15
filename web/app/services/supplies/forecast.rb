module Supplies
  # How fast a supply is used, how many are left now, when it runs out, and when to buy more.
  #
  # 1. Usage samples: between a known count `a` and a later observation `b` at least a day apart,
  #    consumed = a − b + what was bought in between. Negative results (a miscount) are skipped.
  #    Observations closer than a day keep the earlier anchor, so frequent −1 taps still add up.
  # 2. Blend with the starting guess ("one lasts about N days"), worth PRIOR_DAYS of evidence:
  #    rate = (1/N × 14 + Σconsumed) / (14 + Σdays), over the last WINDOW_DAYS.
  # 3. Left now = last known count − rate × days since; runs out on today + left / rate.
  # 4. Buy by = runs out − days it takes to buy − a buffer (bigger while there's little data).
  # Expiry: the earliest batch's units still left on its expiry date, used oldest first.
  class Forecast
    PRIOR_DAYS = 14
    WINDOW_DAYS = 120
    SOON_DAYS = 7

    Sample = Data.define(:consumed, :days, :ended_at)
    Expiring = Data.define(:purchase, :expires_on, :left_at_expiry)

    attr_reader :supply, :today

    def initialize(supply, today:)
      @supply = supply
      @today = today
    end

    def samples
      @samples ||= begin
        list = []
        anchor_at = anchor_level = nil
        added = 0
        Timeline.new(supply).events.each do |event|
          if anchor_at.nil?
            anchor_at, anchor_level, added = event.at, event.level_after, 0
            next
          end
          days = (event.at - anchor_at) / 1.day
          if days >= 1
            consumed = anchor_level + added - event.observed
            list << Sample.new(consumed:, days:, ended_at: event.at) if consumed >= 0
            anchor_at, anchor_level, added = event.at, event.level_after, 0
          else
            added += event.added # bought within the day: counts toward the next sample
          end
        end
        list
      end
    end

    def recent_samples = samples.select { it.ended_at >= now - WINDOW_DAYS.days }

    # Units used per day, nil while there's nothing to go on
    def rate
      return @rate if defined?(@rate)

      prior = supply.guess_days_per_unit ? 1.0 / supply.guess_days_per_unit : nil
      consumed = recent_samples.sum(&:consumed).to_f
      days = recent_samples.sum(&:days).to_f
      @rate = if prior
        (prior * PRIOR_DAYS + consumed) / (PRIOR_DAYS + days)
      elsif days.positive? && consumed.positive?
        consumed / days
      end
    end

    def enough_data? = rate.present? && rate.positive?

    # Fractional estimate; shown rounded ("~2 rolls"), never stored as a count
    def on_hand
      return supply.level.to_f unless enough_data?
      [ supply.level - rate * ((now - supply.level_at) / 1.day), 0.0 ].max
    end

    def on_hand_rounded = on_hand.round

    # True when the shown count is a guess between counts
    def estimated? = enough_data? && on_hand_rounded != supply.level

    def days_left = enough_data? ? on_hand / rate : nil

    def run_out_on
      return nil unless enough_data?
      date = today + days_left.floor
      latest = all_stock_expires_on
      latest && latest < date ? latest : date
    end

    def buffer_days = samples.size >= 3 ? 2 : 4

    def buy_by = run_out_on && run_out_on - supply.lead_days - buffer_days

    def out? = run_out_on ? run_out_on <= today : (supply.level.zero? && supply.purchases.any?)

    def at_alert_level? = supply.alert_when_left.positive? && on_hand_rounded <= supply.alert_when_left

    # Time to buy: on or past the buy-by date, or down to the "alert me when only N left" count
    def buy_now? = out? || (buy_by.present? && buy_by <= today) || at_alert_level?

    def buy_soon? = !buy_now? && buy_by.present? && buy_by <= today + SOON_DAYS

    def needs_buying? = buy_now? || buy_soon?

    # The day it becomes "buy soon" (Supplies › Stocked: "Moves to To Buy on …")
    def to_buy_on = buy_by && buy_by - SOON_DAYS

    # The earliest unexpired batch, when some of it should still be left on its expiry date
    def expiring
      return @expiring if defined?(@expiring)

      @expiring = batches.lazy.filter_map do |purchase|
        next if purchase.expires_on > today + supply.expiry_window_days
        in_stock = [ purchase.quantity.to_f, on_hand ].min
        used_by_then = enough_data? ? rate * (purchase.expires_on - today) : 0
        left = in_stock - used_by_then
        Expiring.new(purchase:, expires_on: purchase.expires_on, left_at_expiry: left.round) if left.round.positive?
      end.first
    end

    def expiring? = expiring.present?

    # :not_enough_data, :out, :buy_now, :buy_soon, :expiring or :ok
    def status
      if out? && enough_data? then :out
      elsif buy_now? then :buy_now
      elsif buy_soon? then :buy_soon
      elsif expiring? then :expiring
      elsif !enough_data? then :not_enough_data
      else :ok
      end
    end

    # 0–100 for the stock bar: what's left against the last restock's peak
    def fill_percent
      peak = [ supply.purchases.map { it.left_before + it.quantity }.max || 0, supply.level, 1 ].max
      ((on_hand / peak) * 100).clamp(0, 100).round
    end

    private

    def now = Time.current

    # Unexpired batches with an expiry date, earliest first
    def batches
      supply.purchases.select { it.expires_on && it.expires_on >= today }.sort_by(&:expires_on)
    end

    # When every unit on hand is from batches with an expiry date, the latest of those dates
    def all_stock_expires_on
      dated = batches
      return nil if dated.empty? || dated.sum(&:quantity) < on_hand.ceil
      dated.last.expires_on
    end
  end
end
