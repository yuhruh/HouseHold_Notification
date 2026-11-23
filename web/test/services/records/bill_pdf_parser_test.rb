require "test_helper"

class Records::BillPdfParserTest < ActiveSupport::TestCase
  include BillPdfSample

  test "a 中華電信 bill is read in full" do
    bill = Records::BillPdfParser.call(words(CHT).to_json)
    assert bill.learned?
    assert_equal [ "中華電信", "T19683736", "網路/電信", "用戶號碼 Y123456" ], [ bill.name, bill.biller, bill.category_name, bill.account ]
    assert_equal [ 1299, Date.new(2026, 11, 10) ], [ bill.amount, bill.due_on ]
    assert_equal [ Date.new(2026, 9, 16), Date.new(2026, 10, 15) ], [ bill.period_from, bill.period_to ]
    assert_equal [ "1200000000001", "定期付款" ], [ bill.bill_number, bill.autopay ]
  end

  test "a PDF that splits its text into single characters reads the same" do
    bill = Records::BillPdfParser.call(words(letters(CHT)))
    assert_equal [ 1299, Date.new(2026, 11, 10), "用戶號碼 Y123456", "定期付款", "1200000000001" ],
      [ bill.amount, bill.due_on, bill.account, bill.autopay, bill.bill_number ]
    assert_equal Date.new(2026, 9, 16), bill.period_from
  end

  test "a bill paid at the counter has no autopay" do
    rows = CHT.map { |row| row[0] == "定 期 付 款" ? [ "臨櫃繳費", *row[1..] ] : row }
    assert_nil Records::BillPdfParser.call(words(rows)).autopay
  end

  test "a bill it hasn't learned is read by its labels" do
    bill = Records::BillPdfParser.call(words([
      [ "某某瓦斯股份有限公司 繳費通知單", 200, 40, 600, 30 ],
      [ "應繳金額：NT$864元", 100, 200, 300, 24 ], [ "繳費截止日：2026年12月5日", 600, 200, 320, 24 ],
      [ "使用期間：115.09.01-115.10.31", 100, 240, 400, 24 ]
    ]))
    refute bill.learned?
    assert_nil bill.biller
    assert_equal [ 864, Date.new(2026, 12, 5), Date.new(2026, 9, 1), Date.new(2026, 10, 31) ], [ bill.amount, bill.due_on, bill.period_from, bill.period_to ]
    assert_nil bill.account
  end

  test "no amount due or no due date: not a bill" do
    assert_raises(Records::BillPdfParser::Invalid) { Records::BillPdfParser.call(words([ [ "電子發票證明聯 總計 120", 100, 100, 300, 24 ] ])) }
    assert_raises(Records::BillPdfParser::Invalid) { Records::BillPdfParser.call(words(CHT.reject { it[0] == "115/11/10" })) }
    assert_raises(Records::BillPdfParser::Invalid) { Records::BillPdfParser.call("[]") }
    assert_raises(Records::BillPdfParser::Invalid) { Records::BillPdfParser.call("not json") }
  end
end
