require "test_helper"

# What each receipt line is matched to on Review items: remembered for the store, an item's name, or
# one of its brands, including the items combined into it
class Supplies::ImportReceiptTest < ActiveSupport::TestCase
  Receipt = Supplies::EInvoiceParser::Receipt
  Item = Supplies::EInvoiceParser::Item

  setup do
    @home = households(:home)
    @alex = users(:alex)
  end

  def item(name) = @home.supplies.create!(name:, kind: "food_drink", unit: "bag", level: 0)

  def receipt(*texts, seller: "11111111", no: "AB00000001")
    Receipt.new(invoice_no: no, issued_on: @home.today, total: 100 * texts.size, seller_tax_id: seller,
                items: texts.map { Item.new(text: it, quantity: 1, unit_price: 100) })
  end

  def rows(receipt) = Supplies::ImportReceipt.rows(@home, receipt).map { [ it.supply&.name, it.tag, it.matched ] }

  def buy(supply, product: nil)
    Supplies::LogPurchase.call(supply, { quantity: 1, total_price: 100, purchased_on: @home.today, product_name: product }.compact, user: @alex)
  end

  def combine(source, target) = Supplies::Combine.call(source.reload, into: target.reload, user: @alex)

  test "a line naming an item combined into another is matched to that item, from any store" do
    coffee = item("Coffee")
    kirkland = item("Kirkland Espresso")
    first = receipt("Kirkland Espresso 1.13kg")
    Supplies::ImportReceipt.call(@home, first, lines: { "0" => { choice: kirkland.id.to_s } }, store: "Costco", user: @alex)
    combine(kirkland, coffee)

    assert_equal [ [ "Coffee", :remembered, nil ] ], rows(receipt("Kirkland Espresso 1.13kg", no: "AB00000002")), "the same store's line, as before"
    assert_equal [ [ "Coffee", :brand, "Kirkland Espresso 1.13kg" ] ], rows(receipt("Kirkland Espresso 1.13kg", seller: "22222222", no: "AB00000003")),
                 "another store: the brand from the purchase, exactly"
    assert_equal [ [ "Coffee", :brand, "Kirkland Espresso 1.13kg" ] ], rows(receipt("KIRKLAND ESPRESSO 1.13KG 2入", seller: "22222222")),
                 "the brand inside a longer line"
    assert_equal [ [ "Coffee", :brand, "Kirkland Espresso 1.13kg" ] ], rows(receipt("Kirkland Espre", seller: "22222222")),
                 "a line cut short, inside the brand"
  end

  test "an item combined with no purchases, prices or barcodes is still known by its name" do
    coffee = item("Coffee")
    combine(item("Starbucks House Blend"), coffee)
    assert_equal [ "Starbucks House Blend" ], coffee.reload.former_names

    assert_equal [ [ "Coffee", :brand, "Starbucks House Blend" ] ], rows(receipt("Starbucks House Blend 250g"))
  end

  test "combined twice: the first item's name follows to the last" do
    coffee = item("Coffee")
    beans = item("Coffee beans")
    combine(item("Lavazza Oro"), beans)
    combine(beans, coffee)

    assert_equal [ "Lavazza Oro", "Coffee beans" ].sort, coffee.reload.former_names.sort
    assert_equal [ [ "Coffee", :brand, "Lavazza Oro" ] ], rows(receipt("Lavazza Oro 1kg"))
  end

  test "the longest name in the line wins, and the loose guess uses item names only" do
    coffee = item("Coffee")
    milk = item("Oat milk")
    buy(milk, product: "Oatly Barista Edition")

    assert_equal [ [ "Coffee", :suggested, "Coffee" ] ], rows(receipt("Coffee beans dark roast"))
    assert_equal [ [ "Oat milk", :brand, "Oatly Barista Edition" ] ], rows(receipt("Oatly Barista Edition 1L"))
    assert_equal [ [ nil, nil, nil ] ], rows(receipt("Baristas")), "shares letters with a brand, not with an item: not a guess"
    assert_equal [ [ nil, nil, nil ] ], rows(receipt("Ba")), "too short to be inside a brand's name"
    assert_equal coffee, Supplies::ImportReceipt.rows(@home, receipt("Coffee")).sole.supply
  end

  test "an old price's and a barcode's product names are brands too; an archived item's are not" do
    shampoo = item("Shampoo")
    shampoo.prices.create!(household: @home, product_name: "Promise Volume Shampoo", total_price: 199, quantity: 1, purchased_on: @home.today)
    shampoo.barcodes.create!(household: @home, code: "4710000000017", product_name: "PDRN Care Shampoo")
    old = item("Old soap")
    buy(old, product: "Dove Beauty Bar")
    old.update!(archived_at: Time.current)

    assert_equal [ [ "Shampoo", :brand, "Promise Volume Shampoo" ], [ "Shampoo", :brand, "PDRN Care Shampoo" ], [ nil, nil, nil ] ],
                 rows(receipt("Promise Volume Shampoo 500ml", "PDRN Care Shampoo", "Dove Beauty Bar"))
  end

  test "a brand bought before in packs gets the size it came in then" do
    snack = item("Pet snack")
    Supplies::LogPurchase.call(snack, { quantity: 6, total_price: 360, purchased_on: @home.today, product_name: "Brand A chicken", pack_size: 4 }, user: @alex)
    Supplies::ImportReceipt.call(@home, receipt("Brand A chicken", "Brand B tuna"), lines: { "0" => { choice: snack.id.to_s }, "1" => { choice: snack.id.to_s } }, store: "PX Mart", user: @alex)

    assert_equal [ [ "Brand A chicken", 4 ], [ "Brand B tuna", nil ] ], snack.purchases.where(store: "PX Mart").order(:id).pluck(:product_name, :pack_size)
  end
end
