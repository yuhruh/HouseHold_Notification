require "test_helper"

class Supplies::ForecastTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    travel_to Time.zone.local(2026, 11, 1, 10)
    @supply = @home.supplies.create!(name: "Toilet paper", kind: "toiletries", unit: "roll", level: 0, lead_days: 3)
  end

  teardown { travel_back }

  def buy(quantity, on:, left_before:, expires_on: nil, total: 289)
    travel_to(on.in_time_zone.change(hour: 10)) do
      Supplies::LogPurchase.call(@supply, { quantity:, total_price: total, purchased_on: Date.current, left_before:, expires_on: }, user: nil).tap { assert it.persisted?, it.errors.full_messages.inspect }
    end
  end

  def count(level, on:)
    travel_to(on.in_time_zone.change(hour: 10)) { Supplies::RecordCount.call(@supply, level, user: nil) }
  end

  def forecast(on) = @supply.reload.forecast(today: on.to_date)

  test "no guess and no history: not enough data yet, no dates" do
    f = forecast(Date.current)
    assert_equal :not_enough_data, f.status
    assert_nil f.run_out_on
    assert_not f.needs_buying?
  end

  test "a starting guess alone gives a date" do
    @supply.update!(guess_days_per_unit: 2, level: 10, level_at: Time.current)
    f = forecast(Date.current)
    assert_in_delta 0.5, f.rate, 0.001
    assert_equal Date.current + 20, f.run_out_on
    assert_equal Date.current + 20 - 3 - 4, f.buy_by, "lead time plus the bigger buffer while there's little data"
  end

  test "the doc example: 12 on Nov 1, 4 left on Nov 20 → about 0.42 a day, ~2 rolls on Nov 25, out about Nov 29" do
    buy(12, on: Date.new(2026, 11, 1), left_before: 0)
    count(4, on: Date.new(2026, 11, 20))
    travel_to Time.zone.local(2026, 11, 25, 10)
    f = forecast(Date.current)
    assert_in_delta 8.0 / 19, f.rate, 0.001
    assert_equal 2, f.on_hand_rounded
    assert f.estimated?
    assert_equal Date.new(2026, 11, 29), f.run_out_on
    assert f.buy_now?, "past the buy-by date"
  end

  test "the guess fades as real usage comes in" do
    @supply.update!(guess_days_per_unit: 10)
    buy(30, on: Date.new(2026, 11, 1), left_before: 0)
    count(20, on: Date.new(2026, 11, 11))
    count(10, on: Date.new(2026, 11, 21))
    count(0, on: Date.new(2026, 12, 1))
    rate = forecast(Date.new(2026, 12, 1)).rate
    assert_in_delta (0.1 * 14 + 30) / (14 + 30), rate, 0.001
    assert rate > 0.6
  end

  test "purchases between counts count as used stock, and a miscount is skipped" do
    buy(10, on: Date.new(2026, 11, 1), left_before: 0)
    buy(10, on: Date.new(2026, 11, 6), left_before: 5) # used 5 in 5 days
    count(25, on: Date.new(2026, 11, 8)) # more than there could be: skipped
    count(15, on: Date.new(2026, 11, 13)) # used 10 in 5 days
    samples = forecast(Date.new(2026, 11, 13)).samples
    assert_equal [ 5, 10 ], samples.map(&:consumed)
  end

  test "−1 taps within a day add up to one sample" do
    buy(6, on: Date.new(2026, 11, 1), left_before: 0)
    travel_to(Time.zone.local(2026, 11, 3, 9)) { Supplies::RecordCount.used_one(@supply, user: nil) }
    travel_to(Time.zone.local(2026, 11, 3, 20)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    travel_to(Time.zone.local(2026, 11, 5, 9)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    assert_equal [ 1, 2 ], forecast(Date.new(2026, 11, 5)).samples.map(&:consumed)
    assert_equal 3, @supply.reload.level
  end

  test "alert_when_left alerts by count even when the date is far off" do
    @supply.update!(guess_days_per_unit: 30, alert_when_left: 2, level: 2, level_at: Time.current)
    f = forecast(Date.current)
    assert f.at_alert_level?
    assert f.buy_now?
  end

  test "stock that expires before it's used: expiring, and runs out on the expiry date" do
    @supply.update!(kind: "food_drink", guess_days_per_unit: 2)
    buy(6, on: Date.new(2026, 11, 1), left_before: 0, expires_on: Date.new(2026, 11, 5))
    f = forecast(Date.new(2026, 11, 1))
    assert_equal Date.new(2026, 11, 5), f.run_out_on, "all of it expires before it would run out"
    assert_equal 4, f.expiring.left_at_expiry
    assert f.expiring?
  end

  test "counts must be whole numbers from 0 up" do
    assert_not @supply.counts.new(level: -1).valid?
    assert_not @supply.counts.new(level: 2.5).valid?
    assert_not @supply.purchases.new(household: @home, quantity: 0, total_price: 10, purchased_on: Date.current, left_before: 0, currency: "TWD").valid?
    purchase = @supply.purchases.new(household: @home, quantity: 1, total_price: 10.5, purchased_on: Date.current, left_before: 0, currency: "TWD")
    assert_not purchase.valid?
    assert_includes purchase.errors.details[:total_price].map { it[:error] }, :whole_number
  end
end
