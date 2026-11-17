require "test_helper"

class Supplies::CombineTest < ActiveSupport::TestCase
  PROMISE = "Promise Volume Shampoo".freeze
  PDRN = "PDRN Care Shampoo".freeze

  setup do
    @home = households(:home)
    @alex = users(:alex)
    travel_to Time.zone.local(2026, 11, 20, 10)
  end

  teardown { travel_back }

  def at(on, &) = travel_to(on.in_time_zone.change(hour: 10), &)

  def item(name, on:, **attrs)
    at(on) { @home.supplies.create!(name:, kind: "toiletries", unit: "bottle", level: 0, **attrs) }
  end

  def buy(supply, quantity, on:, left_before: nil, product: nil, price: 300, store: nil)
    at(on) do
      Supplies::LogPurchase.call(supply, { quantity:, total_price: price, store:, purchased_on: Date.current, left_before:, product_name: product }.compact, user: @alex)
                           .tap { assert it.persisted?, it.errors.full_messages.to_sentence }
    end
  end

  def used_one(supply, on:, product: nil) = at(on) { Supplies::RecordCount.used_one(supply.reload, user: @alex, product:) }

  def known(supply) = supply.reload.brands.list.to_h { [ it.key, it.known ] }

  def combine(source, target) = Supplies::Combine.call(source.reload, into: target.reload, user: @alex)

  test "two products saved as two items become one item with two brands, and the counts add up" do
    promise = item(PROMISE, on: Date.new(2026, 11, 1))
    pdrn = item(PDRN, on: Date.new(2026, 11, 1))
    shampoo = item("Shampoo", on: Date.new(2026, 11, 15))
    buy(pdrn, 3, on: Date.new(2026, 11, 2), price: 897, store: "Coupang")
    buy(promise, 2, on: Date.new(2026, 11, 10), price: 499, store: "Summer")

    combine(promise, shampoo)
    assert_equal [ 2, { PROMISE => 2 } ], [ shampoo.reload.level, known(shampoo) ]
    combine(pdrn, shampoo)

    assert_equal 5, shampoo.reload.level
    assert_equal({ PDRN => 3, PROMISE => 2 }, known(shampoo))
    assert shampoo.brands.several?, "Used 1 bottle asks which one"
    assert_equal [ PDRN, PROMISE ], shampoo.purchases.sort_by(&:purchased_on).map(&:product_name)
    assert_equal [ "Shampoo" ], @home.supplies.pluck(:name)
    assert_equal [ "Shampoo", "bottle" ], [ shampoo.name, shampoo.unit ]
    assert_equal 5, shampoo.forecast.full_stock
    assert_empty shampoo.forecast.samples.select { it.consumed.positive? }, "nothing was used, so the forecast learns no usage from the move"

    Supplies::RecordCount.used_one(shampoo, user: @alex, product: PROMISE)
    assert_equal({ PDRN => 3, PROMISE => 1 }, known(shampoo))
  end

  test "each item's own usage is kept: what one used isn't taken from the other's brand, and no usage is invented" do
    pdrn = item(PDRN, on: Date.new(2026, 10, 1))
    promise = item(PROMISE, on: Date.new(2026, 10, 1))
    buy(pdrn, 3, on: Date.new(2026, 10, 2))          # the brand bought first
    buy(promise, 4, on: Date.new(2026, 10, 10))
    used_one(promise, on: Date.new(2026, 10, 20))    # 3 Promise left
    used_one(promise, on: Date.new(2026, 10, 30))    # 2 Promise left
    buy(promise, 2, on: Date.new(2026, 11, 10), left_before: 1) # one more used, then 3 Promise
    before = promise.reload.forecast.samples.sum(&:consumed)
    assert_equal 3, before

    combine(promise, pdrn)

    pdrn.reload
    assert_equal 6, pdrn.level
    assert_equal({ "" => 3, PROMISE => 3 }, known(pdrn), "Promise's bottles were used, not the PDRN bought first (\"\" is the item's own, unnamed stock)")
    assert_equal 3, pdrn.forecast.samples.sum(&:consumed), "the same 3 bottles used, no more and no fewer"
    assert_equal [ 3, 7, 6, 5, 6, 6 ], Supplies::Timeline.new(pdrn).events.map(&:level_after), "every count includes what the other item had then"
    assert_equal [ PDRN, PROMISE, PROMISE ], pdrn.purchases.sort_by(&:at).map(&:display_name)
    pinned = pdrn.counts.max_by(&:at)
    assert_equal [ { "" => 3, PROMISE => 3 }, 1.second ], [ pinned.by_product, pinned.at - pdrn.purchases.map(&:at).max ],
                 "the last purchase's \"1 left before\" would be taken from the oldest brand, so one count right after it sets the shares"
  end

  test "a brand the item already had keeps its name; stock with no purchase joins without one" do
    shampoo = item("Shampoo", on: Date.new(2026, 11, 1))
    buy(shampoo, 2, on: Date.new(2026, 11, 2), product: "Lux")
    other = item("Hair wash", on: Date.new(2026, 11, 3))
    buy(other, 1, on: Date.new(2026, 11, 4), product: "Lux")
    buy(other, 1, on: Date.new(2026, 11, 5))
    loose = item("Old shampoo", on: Date.new(2026, 11, 6))
    at(Date.new(2026, 11, 7)) { Supplies::RecordCount.call(loose, 1, user: @alex) }

    combine(other, shampoo)
    assert_equal({ "Lux" => 3, "Hair wash" => 1 }, known(shampoo))
    combine(loose, shampoo)
    assert_equal 5, shampoo.reload.level
    assert_equal 5, known(shampoo).values.sum
  end

  test "old prices, barcodes, stars and what receipts remembered move; the target keeps its settings" do
    source = item(PROMISE, on: Date.new(2026, 11, 1), guess_days_per_unit: 20, lead_days: 9)
    target = item("Shampoo", on: Date.new(2026, 11, 1), lead_days: 2)
    buy(source, 2, on: Date.new(2026, 11, 2))
    source.prices.create!(household: @home, quantity: 1, total_price: 280, purchased_on: Date.new(2026, 10, 1), currency: "TWD")
    source.barcodes.create!(household: @home, code: "4901234567894")
    source.favorites.create!(user: @alex)
    target.favorites.create!(user: @alex)
    source.favorites.create!(user: users(:google_only))
    match = @home.receipt_item_matches.create!(seller_tax_id: "12345678", receipt_text: "PROMISE 洗髮精", supply: source, units_per_line: 1)

    combine(source, target)

    target.reload
    assert_equal [ PROMISE ], target.prices.map(&:product_name)
    assert_equal [ [ "4901234567894", PROMISE ] ], target.barcodes.map { [ it.code, it.product_name ] }
    assert_equal [ users(:alex).id, users(:google_only).id ].sort, target.favorites.map(&:user_id).sort
    assert_equal target, match.reload.supply
    assert_equal [ 2, 20 ], [ target.lead_days, target.guess_days_per_unit ], "its own settings; the guess only when it had none"
    assert_not Supply.exists?(source.id)
  end

  test "an item can't be combined with itself or with another ledger's item" do
    mine = item("Shampoo", on: Date.new(2026, 11, 1))
    theirs = households(:parents).supplies.create!(name: "Shampoo", kind: "toiletries", unit: "bottle", level: 0)
    assert_raises(ArgumentError) { combine(mine, mine) }
    assert_raises(ArgumentError) { combine(mine, theirs) }
    assert_equal 2, Supply.where(id: [ mine.id, theirs.id ]).count
  end
end
