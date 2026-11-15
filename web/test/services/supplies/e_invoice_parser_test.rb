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
