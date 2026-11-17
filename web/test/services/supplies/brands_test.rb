require "test_helper"

class Supplies::BrandsTest < ActiveSupport::TestCase
  PANTENE = "Pantene Shampoo 700ml".freeze
  LUX = "Lux Shampoo 750ml".freeze

  setup do
    @home = households(:home)
    travel_to Time.zone.local(2026, 11, 1, 10)
    @supply = @home.supplies.create!(name: "Shampoo", kind: "toiletries", unit: "bottle", level: 0)
  end

  teardown { travel_back }

  def buy(quantity, on:, left_before:, product: nil)
    travel_to(on.in_time_zone.change(hour: 10)) do
      Supplies::LogPurchase.call(@supply, { quantity:, total_price: 289, purchased_on: Date.current, left_before:, product_name: product }, user: nil).tap { assert it.persisted?, it.errors.full_messages.inspect }
    end
  end

  def at(on, &) = travel_to(on.in_time_zone.change(hour: 10), &)

  def brands(on = Date.current) = @supply.reload.brands(@supply.forecast(today: on.to_date))

  # product => what is left of it at the last count
  def known(on = Date.current) = brands(on).list.to_h { [ it.key, it.known ] }

  def two_brands
    buy(2, on: Date.new(2026, 9, 28), left_before: 0, product: PANTENE)
    at(Date.new(2026, 10, 20)) { Supplies::RecordCount.used_one(@supply, user: nil) }
    buy(2, on: Date.new(2026, 10, 30), left_before: 1, product: LUX)
  end

  test "one brand is not several, however it was counted" do
    buy(2, on: Date.new(2026, 10, 1), left_before: 0, product: PANTENE)
    at(Date.new(2026, 10, 20)) { Supplies::RecordCount.call(@supply, 5, user: nil) }
    assert_equal({ PANTENE => 5 }, known, "more than was bought joins the brand bought last")
    assert_not brands.several?
  end

  test "each purchase adds to its brand; the one bought first is on top, marked oldest" do
    two_brands
    assert_equal 3, @supply.reload.level
    list = brands.list
    assert_equal [ [ PANTENE, 1, true ], [ LUX, 2, false ] ], list.map { [ it.name, it.known, it.oldest ] }
    assert_equal [ Date.new(2026, 9, 28), Date.new(2026, 10, 30) ], list.map { it.purchase.purchased_on }
    assert brands.several?
    assert_equal [ PANTENE, LUX ], brands.keys
  end

  test "−1 with a brand takes from that brand, and Undo gives it back" do
    two_brands
    count = Supplies::RecordCount.used_one(@supply, user: nil, product: LUX)
    assert_equal 2, @supply.reload.level
    assert_equal({ PANTENE => 1, LUX => 1 }, known)
    Supplies::RecordCount.undo(count)
    assert_equal({ PANTENE => 1, LUX => 2 }, known)
  end

  test "a plain −1 or count takes from the brand bought first" do
    two_brands
    Supplies::RecordCount.used_one(@supply, user: nil)
    assert_equal({ LUX => 2 }, known)
    assert_not brands.several?
    assert_nil brands.find(PANTENE), "a brand with none left is not offered"
    Supplies::RecordCount.call(@supply, 1, user: nil)
    assert_equal({ LUX => 1 }, known)
  end

  test "a count made brand by brand sets each brand; the item's count is their sum" do
    two_brands
    Supplies::RecordCount.by_brand(@supply, { PANTENE => 0, LUX => 3 }, user: nil)
    assert_equal 3, @supply.reload.level
    assert_equal({ LUX => 3 }, known)
    Supplies::RecordCount.by_brand(@supply, { PANTENE => 2, LUX => 1, "Nobody bought this" => 4 }, user: nil)
    assert_equal 7, @supply.reload.level
    assert_equal({ PANTENE => 2, LUX => 5 }, known, "a name no purchase has is ignored; its number joins the brand bought last")
  end

  test "between counts the estimate takes from the brand bought first, so the brands add up to the number shown" do
    @supply.update!(guess_days_per_unit: 10)
    buy(1, on: Date.new(2026, 11, 1), left_before: 0, product: PANTENE)
    buy(2, on: Date.new(2026, 11, 1), left_before: 1, product: LUX)
    later = Date.new(2026, 11, 13)
    at(later) do
      forecast = @supply.reload.forecast(today: later)
      assert_equal 2, forecast.on_hand_rounded
      list = @supply.brands(forecast).list
      assert_equal [ [ PANTENE, 1, 0 ], [ LUX, 2, 2 ] ], list.map { [ it.name, it.known, it.left ] }
      assert @supply.brands(forecast).several?, "Pantene can still be picked: the last count had one"
    end
  end

  test "stock from before the first purchase takes that purchase's brand; a purchase with no product is its own" do
    Supplies::RecordCount.call(@supply, 2, user: nil)
    buy(2, on: Date.new(2026, 11, 2), left_before: 2, product: LUX)
    assert_equal({ LUX => 4 }, known(Date.new(2026, 11, 2)))
    buy(1, on: Date.new(2026, 11, 3), left_before: 4)
    list = brands(Date.new(2026, 11, 3)).list
    assert_equal [ [ LUX, 4 ], [ nil, 1 ] ], list.map { [ it.name, it.known ] }
    assert_equal "", list.last.key
    assert_not list.last.named?
  end

  test "a corrected product name is followed by the counts that named it" do
    two_brands
    Supplies::RecordCount.used_one(@supply, user: nil, product: LUX)
    at(Date.new(2026, 11, 2)) { Supplies::RecordCount.by_brand(@supply, { PANTENE => 1, LUX => 1 }, user: nil) }
    Supplies::PurchaseDetails.for_edit(@supply.reload, { product_name: "Lux 750" }, user: nil, add_to_ledger: false)
    assert_equal [ "Lux 750" ], @supply.reload.counts.filter_map(&:used_product)
    assert_equal({ PANTENE => 1, "Lux 750" => 1 }, @supply.counts.filter_map(&:by_product).sole)
    assert_equal({ PANTENE => 1, "Lux 750" => 1 }, known(Date.new(2026, 11, 2)))
  end
end
