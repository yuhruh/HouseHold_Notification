require "test_helper"

class Supplies::EInvoiceParserTest < ActiveSupport::TestCase
  # AB12345678 · 1151115 (2026-11-15) · random 1234 · sales 0x10E (270) · total 0x11B (283)
  HEAD = "AB12345678" "1151115" "1234" "0000010E" "0000011B" "00000000" "12345678" + ("x" * 24)

  test "two QR codes in either order: number, date, total, seller and every item" do
    left = "#{HEAD}:**********:2:3:1:舒潔衛生紙:1:189:鮮奶:2:45:"
    right = "**洗碗精:1:4"
    receipt = Supplies::EInvoiceParser.call(right, left)
    assert_equal "AB12345678", receipt.invoice_no
    assert_equal Date.new(2026, 11, 15), receipt.issued_on
    assert_equal 283, receipt.total
    assert_equal "12345678", receipt.seller_tax_id
    assert_equal [ "舒潔衛生紙", "鮮奶", "洗碗精" ], receipt.items.map(&:text)
    assert_equal [ 1, 2, 1 ], receipt.items.map(&:quantity)
    assert_equal 90, receipt.items.second.amount
  end

  test "one QR code with all the items" do
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:1:1:1:牙膏:1:99")
    assert_equal [ "牙膏" ], receipt.items.map(&:text)
  end

  test "Big5 item names" do
    names = "衛生紙".encode("Big5").b
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:1:1:0:".b + names + ":1:189".b)
    assert_equal "衛生紙", receipt.items.sole.text
  end

  test "Base64 item names" do
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:1:1:2:#{Base64.strict_encode64('洗衣精:2:150')}")
    assert_equal [ [ "洗衣精", 2, 150 ] ], receipt.items.map { [ it.text, it.quantity, it.unit_price ] }
  end

  test "a quantity or price with an exponent or too many digits is not read" do
    items = [ "皂:1e1000000000:1", "肥皂:1:1e3000000000", "a:1E3:1", "b:1d3:1", "c:1:Infinity", "d:NaN:1",
              "e:1234567890123456:1", "f:1:0.123456789", "牙膏:2:99" ]
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:9:9:1:#{items.join(':')}")
    assert_equal [ [ "牙膏", 2, 99 ] ], receipt.items.map { [ it.text, it.quantity, it.unit_price ] }
  end

  test "a quantity or price written as .5, 3. or with spaces is still read" do
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:3:3:1:米:.5:3.:麵: 2 :+12.25:油:123456789012345:0.12345678")
    expected = [ [ BigDecimal("0.5"), 3 ], [ 2, BigDecimal("12.25") ], [ 123456789012345, BigDecimal("0.12345678") ] ]
    assert_equal expected, receipt.items.map { [ it.quantity, it.unit_price ] }
  end

  test "only the first #{Supplies::EInvoiceParser::MAX_ITEMS} items are read" do
    items = (1..Supplies::EInvoiceParser::MAX_ITEMS + 50).map { "item #{it}:1:10" }
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:150:150:1:#{items.join(':')}")
    expected = (1..Supplies::EInvoiceParser::MAX_ITEMS).map { "item #{it}" }
    assert_equal expected, receipt.items.map(&:text)
  end

  test "no item details: just the total" do
    receipt = Supplies::EInvoiceParser.call("#{HEAD}:**********:0:0:1")
    assert_empty receipt.items
    assert_equal 283, receipt.total
  end

  test "anything else is refused" do
    assert_raises(Supplies::EInvoiceParser::Invalid) { Supplies::EInvoiceParser.call("https://example.com") }
    assert_raises(Supplies::EInvoiceParser::Invalid) { Supplies::EInvoiceParser.call("**only the right one") }
    assert_raises(Supplies::EInvoiceParser::Invalid) { Supplies::EInvoiceParser.call(HEAD.sub("1151115", "1151345")) }
  end
end
