require "test_helper"

# Shampoo counted on Oct 1 ("3 left") before any purchase was logged, then 2 Lux bought on Nov 20
# that expire Mar 12, 2027: the 3 are stock with no purchase behind them
class Supplies::AddStockDetailsTest < ActiveSupport::TestCase
  LUX = "Lux Shampoo 750ml".freeze

  setup do
    @home = households(:home)
    travel_to Time.zone.local(2026, 9, 1, 10)
    @supply = @home.supplies.create!(name: "Shampoo", kind: "toiletries", unit: "bottle", level: 0)
    at(Date.new(2026, 10, 1)) { @count = Supplies::RecordCount.call(@supply, 3, user: nil) }
    at(Date.new(2026, 11, 20)) do
      @dated = Supplies::LogPurchase.call(@supply.reload, { quantity: 2, total_price: 358, purchased_on: Date.current, left_before: 3, product_name: LUX,
                                                           expires_on: Date.new(2027, 3, 12) }, user: nil)
    end
    travel_to Time.zone.local(2026, 11, 20, 18)
  end

  teardown { travel_back }

  def at(on, &) = travel_to(on.in_time_zone.change(hour: 10), &)

  def batches = @supply.reload.brands.batches.map { [ it.purchase, it.left ] }

  def details = Supplies::AddStockDetails.new(@supply.reload)

  def old_price(on, quantity:, total:, product: LUX, store: "Costco")
    @supply.prices.create!(household: @home, purchased_on: on, quantity:, total_price: total, product_name: product, store:, currency: "TWD")
  end

  test "the stock with no purchase is a batch of its own, and its −1 takes from it" do
    assert_equal [ [ @dated, 2 ], [ nil, 3 ] ], batches
    batch = @supply.brands.find_batch(Supplies::Brands::NO_PURCHASE)
    assert_equal 3, batch.left
    assert_equal LUX, batch.product
    assert_equal @count, @supply.brands.no_purchase_counted

    count = Supplies::RecordCount.used_one(@supply, user: nil, product: batch.product, no_purchase: true)
    assert count.used_no_purchase
    assert_equal [ [ @dated, 2 ], [ nil, 2 ] ], batches, "not from the batch to use first"

    Supplies::RecordCount.undo(count)
    assert_equal [ [ @dated, 2 ], [ nil, 3 ] ], batches
  end

  test "old prices on or before the day it was counted are the choices, newest first" do
    aug = old_price(Date.new(2026, 8, 2), quantity: 2, total: 398, product: "Pantene Shampoo 700ml", store: "Carrefour")
    sep = old_price(Date.new(2026, 9, 15), quantity: 4, total: 716)
    old_price(Date.new(2026, 10, 2), quantity: 1, total: 189)
    assert_equal Date.new(2026, 10, 1), details.last_day
    assert_equal [ sep, aug ], details.choices
  end

  test "choosing an old price makes it the purchase those came from, listed once, and the −1s taken name it" do
    sep = old_price(Date.new(2026, 9, 15), quantity: 4, total: 716)
    used = Supplies::RecordCount.used_one(@supply, user: nil, product: LUX, no_purchase: true)
    level = @supply.reload.level

    purchase = details.from_price(sep, quantity: "4", expires_on: "2027-01-20", user: users(:alex), add_to_ledger: false)
    assert purchase.persisted?, purchase.errors.full_messages.inspect
    assert_not SupplyPrice.exists?(sep.id)
    assert_equal [ Date.new(2026, 9, 15), 4, 716, "Costco", LUX, Date.new(2027, 1, 20) ],
                 purchase.slice(:purchased_on, :quantity, :total_price, :store, :product_name, :expires_on).values
    assert_operator purchase.at, :<, @count.at
    assert_nil purchase.record

    assert_equal [ [ purchase, 2 ], [ @dated, 2 ] ], batches, "it expires first now"
    assert_nil @supply.brands.no_purchase_batch
    assert_equal purchase, used.reload.used_purchase
    assert_not used.used_no_purchase
    assert_equal [ @dated, purchase ], @supply.price_history
    assert_equal level, @supply.level
  end

  test "the details typed in, with no price: saved without one, left out of prices, and no Ledger expense" do
    purchase = details.entered({ purchased_on: "2026-09-01", quantity: "3", expires_on: "", product_name: "", store: "", total_price: "", paid_currency: "TWD" },
                               user: users(:alex), add_to_ledger: true)
    assert purchase.persisted?, purchase.errors.full_messages.inspect
    assert_nil purchase.total_price
    assert_nil purchase.record
    assert_equal [ [ @dated, 2 ], [ purchase, 3 ] ], batches
    assert_equal [ @dated ], @supply.price_history
    assert_equal @dated, @supply.latest_priced_purchase

    # Corrected later on Edit item, it may stay without a price
    edited = Supplies::PurchaseDetails.for_edit(@supply, { expires_on: "2027-02-01", total_price: "" }, user: users(:alex), add_to_ledger: false, purchase:)
    assert edited.valid?, edited.errors.full_messages.inspect
    assert_equal Date.new(2027, 2, 1), purchase.reload.expires_on
  end

  test "bought on the day it was counted goes before that count; with a price, Also add to Ledger adds the expense" do
    purchase = details.entered({ purchased_on: "2026-10-01", quantity: "3", total_price: "540", store: "Costco" }, user: users(:alex), add_to_ledger: true)
    assert purchase.persisted?, purchase.errors.full_messages.inspect
    assert_operator purchase.at, :<, @count.at
    assert_equal [ [ @dated, 2 ], [ purchase, 3 ] ], batches
    assert_equal 540, purchase.record.amount_paid
  end

  test "refused: bought after the day it was counted, or fewer than were counted then" do
    late = details.entered({ purchased_on: "2026-10-02", quantity: "3" }, user: nil, add_to_ledger: false)
    assert_not late.persisted?
    assert late.errors.of_kind?(:purchased_on, :after_count)

    few = details.entered({ purchased_on: "2026-09-01", quantity: "2" }, user: nil, add_to_ledger: false)
    assert_not few.persisted?
    assert few.errors.of_kind?(:quantity, :fewer_than_counted)
    assert_equal [ [ @dated, 2 ], [ nil, 3 ] ], batches
  end

  test "a purchase still needs a price everywhere else" do
    purchase = Supplies::LogPurchase.call(@supply, { quantity: 1, purchased_on: Date.current, left_before: 5 }, user: nil)
    assert_not purchase.persisted?
    assert purchase.errors.key?(:total_price)
  end
end
