require "test_helper"

class Supplies::AlertsTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    travel_to Time.zone.local(2026, 11, 1, 10)
    @supply = @home.supplies.create!(name: "Shampoo", kind: "toiletries", unit: "bottle", level: 0, lead_days: 3, guess_days_per_unit: 10)
    Supplies::LogPurchase.call(@supply, { quantity: 2, total_price: 398, purchased_on: Date.current, left_before: 0, store: "Watsons" }, user: nil)
  end

  teardown { travel_back }

  def alerts(on)
    travel_to(on.in_time_zone.change(hour: 9)) { I18n.with_locale(:en) { Supplies::Alerts.call(@home).map { [ it.kind, it.text ] } } }
  end

  test "low on the buy-by date once, out on the run-out date once, then a restock starts over" do
    assert_empty alerts(Date.new(2026, 11, 5))
    low = alerts(Date.new(2026, 11, 14)) # 20 days of stock → out Nov 21, buy by Nov 14
    assert_equal [ :low ], low.map(&:first)
    assert_match "Shampoo: about 1 bottle left, should run out around Nov 21. Buy by Nov 14. (Last bought at Watsons, 2 for NT$398.)", low.sole.last
    assert_empty alerts(Date.new(2026, 11, 15)), "sent once"
    assert_equal [ :out ], alerts(Date.new(2026, 11, 21)).map(&:first)
    assert_empty alerts(Date.new(2026, 11, 22))

    travel_to(Time.zone.local(2026, 11, 22, 12)) do
      Supplies::LogPurchase.call(@supply.reload, { quantity: 3, total_price: 597, purchased_on: Date.current, left_before: 0 }, user: nil)
    end
    assert_equal "ok", @supply.reload.alert_state
    assert_empty alerts(Date.new(2026, 11, 23))
  end

  test "expiry alerts once per batch, within the item's window" do
    @supply.update!(kind: "food_drink")
    travel_to(Time.zone.local(2026, 11, 2, 12)) do
      Supplies::LogPurchase.call(@supply.reload, { quantity: 6, total_price: 300, purchased_on: Date.current, left_before: 2, expires_on: Date.new(2026, 11, 20) }, user: nil)
    end
    assert_not_includes alerts(Date.new(2026, 11, 3)).map(&:first), :expiry, "more than 7 days away"
    expiry = alerts(Date.new(2026, 11, 13)).select { it.first == :expiry }
    assert_equal 1, expiry.size
    assert_match "will expire on Nov 20", expiry.sole.last
    assert_empty alerts(Date.new(2026, 11, 14)).select { it.first == :expiry }
  end

  test "archived items don't alert" do
    @supply.update!(archived_at: Time.current)
    assert_empty alerts(Date.new(2026, 11, 14))
  end
end
