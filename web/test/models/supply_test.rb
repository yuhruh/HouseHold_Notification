require "test_helper"

# A pack size is per brand: on each purchase and old price (Priced), never the item
class SupplyTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    @snack = @home.supplies.create!(name: "Pet snack", unit: "pack", level: 0)
  end

  def buy(product, quantity, total, size: nil, inner: nil, on: @home.today, store: nil)
    Supplies::LogPurchase.call(@snack, { quantity:, total_price: total, purchased_on: on, product_name: product, store:, pack_size: size, pack_unit: inner }, user: nil)
  end

  test "a purchase keeps its size, inside is pieces unless said, and a size of 1, 1000 or 2.5 is refused" do
    purchase = buy("Brand A", 6, 360, size: 4)
    assert purchase.persisted?
    assert_equal [ 4, "piece" ], [ purchase.pack_size, purchase.pack_unit ]
    assert purchase.packed?
    assert_equal 15, purchase.piece_price
    assert_nil buy("Brand C", 1, 50, inner: "roll").pack_unit, "no size, nothing inside"
    [ 1, 1000, 2.5 ].each { assert_not @snack.purchases.new(quantity: 1, total_price: 1, purchased_on: @home.today, pack_size: it).valid?, it.to_s }
    assert_not @snack.prices.new(household: @home, quantity: 1, total_price: 1, purchased_on: @home.today, pack_size: 4, pack_unit: "pack").valid?
  end

  test "each brand keeps its own size; the newest one counts, and the item's own name is no brand" do
    buy("Brand A", 6, 360, size: 4, on: @home.today - 20)
    buy("Brand B", 2, 480, size: 20)
    buy("Brand A", 3, 200, size: 5, on: @home.today - 5)
    buy(nil, 1, 100, size: 10, inner: "roll")
    @snack.prices.create!(household: @home, product_name: "Brand B", quantity: 1, total_price: 230, purchased_on: @home.today - 40, pack_size: 25)

    assert_equal({ "Brand A" => [ 5, "piece" ], "Brand B" => [ 20, "piece" ], "" => [ 10, "roll" ] }, @snack.reload.pack_sizes)
    assert_equal [ 20, "piece" ], @snack.pack_size_for("Brand B")
    assert_equal [ 10, "roll" ], @snack.pack_size_for("Pet snack")
    assert_nil @snack.pack_size_for("Brand Z")
  end

  test "Cheapest compares per piece when every price has a size of the same kind, else per pack" do
    a = buy("Brand A", 6, 360, size: 4, store: "Costco")   # NT$60 a pack, NT$15 a piece
    b = buy("Brand B", 2, 480, size: 20, store: "PX Mart") # NT$240 a pack, NT$12 a piece
    assert_equal b, @snack.reload.priced.min_by(&@snack.cheaper_first)

    buy("Brand C", 1, 100, store: "Carrefour") # no size
    assert_equal a, @snack.reload.priced.min_by(&@snack.cheaper_first), "per pack again"

    @snack.update!(unit: "piece")
    assert_not b.reload.packed?, "set aside while counted in pieces"
    @snack.update!(unit: "pack")
    assert b.reload.packed?, "and back"
  end
end
