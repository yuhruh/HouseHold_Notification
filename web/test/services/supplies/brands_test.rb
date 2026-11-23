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

  def buy(quantity, on:, left_before:, product: nil, expires: nil)
    travel_to(on.in_time_zone.change(hour: 10)) do
      Supplies::LogPurchase.call(@supply, { quantity:, total_price: 289, purchased_on: Date.current, left_before:, product_name: product, expires_on: expires }, user: nil).tap { assert it.persisted?, it.errors.full_messages.inspect }
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

  test "a restock logged late is still the older stock when it was bought first" do
    buy(1, on: Date.new(2026, 10, 30), left_before: 0, product: LUX)
    at(Date.new(2026, 11, 1)) do
      Supplies::LogPurchase.call(@supply.reload, { quantity: 1, total_price: 120, purchased_on: Date.new(2026, 9, 3), left_before: 1, product_name: PANTENE }, user: nil)
    end
    assert_equal 2, @supply.reload.level
    assert_equal [ [ PANTENE, 1, true ], [ LUX, 1, false ] ], brands.list.map { [ it.name, it.known, it.first ] }

    at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    assert_equal({ LUX => 1 }, known(Date.new(2026, 11, 2)), "a plain −1 takes the one bought in September")
  end

  test "with expiry dates the brand that expires first is on top, whichever was bought first, and usage is taken from it" do
    buy(2, on: Date.new(2026, 9, 28), left_before: 0, product: PANTENE, expires: Date.new(2028, 6, 30))
    buy(2, on: Date.new(2026, 10, 30), left_before: 2, product: LUX, expires: Date.new(2027, 3, 12))
    list = brands.list
    assert_equal [ [ LUX, 2, true ], [ PANTENE, 2, false ] ], list.map { [ it.name, it.known, it.first ] }
    assert_equal [ Date.new(2027, 3, 12), Date.new(2028, 6, 30) ], list.map(&:expires_on)

    at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    assert_equal({ PANTENE => 2, LUX => 1 }, known(Date.new(2026, 11, 2)), "a plain −1 takes the one that expires first")
    at(Date.new(2026, 11, 3)) { Supplies::RecordCount.call(@supply.reload, 1, user: nil) }
    assert_equal({ PANTENE => 1 }, known(Date.new(2026, 11, 3)), "a count of the whole item empties it before the other")
  end

  test "a brand with an expiry date comes before one with none, even when the other was bought earlier" do
    buy(1, on: Date.new(2026, 9, 28), left_before: 0, product: PANTENE)
    buy(1, on: Date.new(2026, 10, 30), left_before: 1, product: LUX, expires: Date.new(2027, 3, 12))
    assert_equal [ [ LUX, true, Date.new(2027, 3, 12) ], [ PANTENE, false, nil ] ], brands.list.map { [ it.name, it.first, it.expires_on ] }
  end

  test "a brand bought twice goes by its batch that expires first and still has some left" do
    buy(1, on: Date.new(2026, 9, 1), left_before: 0, product: LUX, expires: Date.new(2027, 1, 31))
    buy(1, on: Date.new(2026, 9, 28), left_before: 1, product: PANTENE, expires: Date.new(2027, 6, 30))
    buy(1, on: Date.new(2026, 10, 30), left_before: 2, product: LUX, expires: Date.new(2028, 1, 31))
    assert_equal [ [ LUX, Date.new(2027, 1, 31) ], [ PANTENE, Date.new(2027, 6, 30) ] ], brands.list.map { [ it.name, it.expires_on ] }

    at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil, product: LUX) }
    assert_equal [ [ PANTENE, Date.new(2027, 6, 30) ], [ LUX, Date.new(2028, 1, 31) ] ], brands(Date.new(2026, 11, 2)).list.map { [ it.name, it.expires_on ] },
                 "the Lux that expired first is used, so the Lux left is the 2028 one"
  end

  test "with no expiry dates, two brands bought the same day: the one entered first is on top" do
    buy(1, on: Date.new(2026, 9, 3), left_before: 0, product: PANTENE)
    travel_to(Time.zone.local(2026, 9, 3, 11)) { Supplies::LogPurchase.call(@supply.reload, { quantity: 1, total_price: 120, purchased_on: Date.new(2026, 9, 3), left_before: 1, product_name: LUX }, user: nil) }
    assert_equal [ [ PANTENE, true, nil ], [ LUX, false, nil ] ], brands.list.map { [ it.name, it.first, it.expires_on ] }
  end

  test "each purchase adds to its brand; the one bought first is on top, marked first" do
    two_brands
    assert_equal 3, @supply.reload.level
    list = brands.list
    assert_equal [ [ PANTENE, 1, true ], [ LUX, 2, false ] ], list.map { [ it.name, it.known, it.first ] }
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

  test "one brand restocked before it ran out: each batch with what is left of it, the one that expires first on top" do
    old = buy(2, on: Date.new(2026, 9, 3), left_before: 0, product: LUX, expires: Date.new(2027, 3, 12))
    at(Date.new(2026, 10, 1)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    new = buy(2, on: Date.new(2026, 10, 30), left_before: 1, product: LUX, expires: Date.new(2028, 1, 15))

    assert_not brands.several?
    assert brands.several_batches?
    assert_equal [ [ old, 1, true ], [ new, 2, false ] ], brands.batches.map { [ it.purchase, it.left, it.first ] }
    assert_equal [ [ old, 1 ], [ new, 2 ] ], brands.list.first.batches.map { [ it.purchase, it.left ] }
    assert_equal 2, brands.left_of(new)

    at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil) }
    assert_not brands(Date.new(2026, 11, 2)).several_batches?, "a plain −1 used the old one up"
    assert_equal [ [ new, 2 ] ], brands(Date.new(2026, 11, 2)).batches.map { [ it.purchase, it.left ] }
  end

  test "a restock that expires sooner than what was left goes on top" do
    old = buy(1, on: Date.new(2026, 9, 3), left_before: 0, product: LUX, expires: Date.new(2027, 3, 12))
    new = buy(2, on: Date.new(2026, 10, 30), left_before: 1, product: LUX, expires: Date.new(2027, 2, 20))
    assert_equal [ [ new, true ], [ old, false ] ], brands.batches.map { [ it.purchase, it.first ] }
  end

  test "−1 on one batch takes from that batch, not the one to use first, and Undo gives it back" do
    old = buy(1, on: Date.new(2026, 9, 3), left_before: 0, product: LUX, expires: Date.new(2027, 3, 12))
    new = buy(2, on: Date.new(2026, 10, 30), left_before: 1, product: LUX, expires: Date.new(2028, 1, 15))
    count = at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil, product: LUX, purchase: new) }
    assert_equal new, count.reload.used_purchase
    assert_equal [ [ old, 1 ], [ new, 1 ] ], brands(Date.new(2026, 11, 2)).batches.map { [ it.purchase, it.left ] }

    Supplies::RecordCount.undo(count)
    assert_equal [ [ old, 1 ], [ new, 2 ] ], brands(Date.new(2026, 11, 2)).batches.map { [ it.purchase, it.left ] }
  end

  test "a −1 whose batch was deleted counts as one of its brand" do
    buy(1, on: Date.new(2026, 9, 3), left_before: 0, product: LUX, expires: Date.new(2027, 3, 12))
    new = buy(2, on: Date.new(2026, 10, 30), left_before: 1, product: LUX, expires: Date.new(2028, 1, 15))
    count = at(Date.new(2026, 11, 2)) { Supplies::RecordCount.used_one(@supply.reload, user: nil, product: LUX, purchase: new) }
    new.destroy!
    assert_nil count.reload.used_purchase_id
    assert_equal({ LUX => 2 }, known(Date.new(2026, 11, 2)))
  end

  test "two brands: only the one bought twice lists its batches" do
    buy(1, on: Date.new(2026, 9, 3), left_before: 0, product: LUX, expires: Date.new(2027, 3, 12))
    buy(1, on: Date.new(2026, 10, 10), left_before: 1, product: PANTENE, expires: Date.new(2027, 8, 1))
    buy(2, on: Date.new(2026, 10, 30), left_before: 2, product: LUX, expires: Date.new(2028, 1, 15))
    lux, pantene = brands.list
    assert_equal [ LUX, PANTENE ], [ lux.name, pantene.name ]
    assert lux.several_batches?
    assert_not pantene.several_batches?
    assert_equal [ 1, 2 ], lux.batches.map(&:left)
    assert_not brands.several_batches?, "several brands: the batches show under each brand"
  end
end
