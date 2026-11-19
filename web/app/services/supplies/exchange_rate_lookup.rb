module Supplies
  # What one unit of a currency was worth in another on a day: the rate a purchase abroad is turned
  # into the household's currency with. It is the rate for the day of the purchase, not the day it
  # is typed in.
  #
  # Asked of the rates already kept (exchange_rates) first, then of Frankfurter, a free service that
  # collects central banks' daily rates. Only two currency codes and a date leave the app, with a
  # generic User-Agent. A day whose rate isn't out yet gets the latest one, and the answer says
  # which day it is for. Any failure is "no rate": the form then asks for the amount instead.
  class ExchangeRateLookup
    URL = "https://api.frankfurter.dev/v2/rates"

    # on: the day the rate is for, which can be earlier than the day asked about
    Result = Data.define(:rate, :on)

    # fetcher: ->(url) { body string, or nil on any failure }; tests pass their own
    def self.call(from:, to:, on:, fetcher: nil)
      new(from:, to:, on:, fetcher: fetcher || method(:fetch)).call
    end

    def self.fetch(url) = BarcodeLookup.fetch(url)

    def initialize(from:, to:, on:, fetcher:)
      @from = from.to_s
      @to = to.to_s
      @on = on
      @fetcher = fetcher
    end

    def call
      return nil unless Currency.known?(@from) && Currency.known?(@to) && @on.is_a?(Date)
      return Result.new(rate: BigDecimal(1), on: @on) if @from == @to

      kept = ::ExchangeRate.find_by(base: @from, quote: @to, rated_on: @on)
      kept = remember(kept) unless kept&.fresh?
      kept && Result.new(rate: kept.rate, on: kept.published_on)
    end

    private

    # An older answer is still better than none when the service can't be reached
    def remember(kept)
      found = ask(@on) || ask(nil)
      return kept unless found

      kept ||= ::ExchangeRate.new(base: @from, quote: @to, rated_on: @on)
      kept.update!(rate: found[:rate], published_on: found[:on], fetched_at: Time.current)
      kept
    rescue ActiveRecord::RecordNotUnique
      ::ExchangeRate.find_by(base: @from, quote: @to, rated_on: @on)
    end

    # → { rate:, on: } for that day, or the latest rate without one
    def ask(date)
      query = { base: @from, quotes: @to }
      query[:date] = date.iso8601 if date
      body = @fetcher.call("#{URL}?#{URI.encode_www_form(query)}")
      row = body && Array(JSON.parse(body)).find { it.is_a?(Hash) && it["base"] == @from && it["quote"] == @to }
      return nil unless row

      rate = BigDecimal(row["rate"].to_s)
      rate.positive? ? { rate:, on: Date.iso8601(row["date"].to_s) } : nil
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end
  end
end
