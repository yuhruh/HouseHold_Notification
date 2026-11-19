require "test_helper"

class Supplies::ExchangeRateLookupTest < ActiveSupport::TestCase
  setup do
    @urls = []
    @day = Date.new(2026, 11, 16)
  end

  # answers: what the service says for a date ("2026-11-16"), or without one (:latest)
  def lookup(from: "JPY", to: "TWD", on: @day, answers: {})
    urls = @urls
    fetcher = ->(url) { urls << url; answers[url[/date=([\d-]+)/, 1] || :latest] }
    Supplies::ExchangeRateLookup.call(from:, to:, on:, fetcher:)
  end

  def answer(rate, date) = [ { date:, base: "JPY", quote: "TWD", rate: } ].to_json

  test "the rate for the day asked about: only two currency codes and a date leave the app, and the answer is kept" do
    result = lookup(answers: { "2026-11-16" => answer(0.20612, "2026-11-16") })
    assert_equal [ BigDecimal("0.20612"), @day ], [ result.rate, result.on ]
    assert_equal [ "https://api.frankfurter.dev/v2/rates?base=JPY&quotes=TWD&date=2026-11-16" ], @urls

    @urls.clear
    assert_equal BigDecimal("0.20612"), lookup.rate, "kept: the same for every household"
    assert_empty @urls
    assert_equal BigDecimal("0.20124"), lookup(on: Date.new(2026, 9, 3), answers: { "2026-09-03" => answer(0.20124, "2026-09-03") }).rate, "another day is another rate"
  end

  test "a day whose rate isn't out yet gets the latest one, says which day it is for, and is asked again later" do
    travel_to Time.utc(2026, 11, 16, 2) do
      result = lookup(answers: { "2026-11-16" => "[]", latest: answer(0.20598, "2026-11-13") })
      assert_equal [ BigDecimal("0.20598"), Date.new(2026, 11, 13) ], [ result.rate, result.on ]
      assert_equal 2, @urls.size
      assert_not_includes @urls.last, "date="

      @urls.clear
      assert_equal BigDecimal("0.20598"), lookup.rate
      assert_empty @urls, "not asked again straight away"
    end

    travel_to Time.utc(2026, 11, 16, 10) do
      result = lookup(answers: { "2026-11-16" => answer(0.20612, "2026-11-16") })
      assert_equal [ BigDecimal("0.20612"), @day ], [ result.rate, result.on ]
      assert_equal 1, ExchangeRate.count
    end
  end

  test "no answer is no rate; an answer already kept is still used when the service can't be reached" do
    assert_nil lookup
    assert_nil lookup(answers: { "2026-11-16" => "<html>Challenge</html>", latest: "nope" })
    assert_nil lookup(answers: { "2026-11-16" => answer(0, "2026-11-16") })
    assert_equal 0, ExchangeRate.count

    travel_to Time.utc(2026, 11, 16, 2) do
      lookup(answers: { latest: answer(0.20598, "2026-11-13") })
    end
    travel_to Time.utc(2026, 11, 17, 2) do
      assert_equal BigDecimal("0.20598"), lookup.rate
    end
  end

  test "a currency that isn't on the list, or something that isn't a date, asks nothing; the same currency is 1" do
    assert_nil lookup(from: "XXX")
    assert_nil lookup(to: "BTC")
    assert_nil lookup(on: "2026-11-16")
    assert_equal BigDecimal(1), lookup(from: "TWD").rate
    assert_empty @urls
  end
end
