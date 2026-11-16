require "test_helper"

class Supplies::InvoicePdfParserTest < ActiveSupport::TestCase
  def word(s, x, y, w = s.size * 9, h = 9) = { "s" => s, "x" => x, "y" => y, "w" => w, "h" => h }

  test "a store's 發票明細 PDF as pdf.js reads it: seller, number, date, total, and items with wrapped names" do
    receipt = Supplies::InvoicePdfParser.call(file_fixture("einvoice/invoice_pdf_words.json").read)
    assert_equal "HX45765353", receipt.invoice_no
    assert_equal Date.new(2026, 11, 2), receipt.issued_on
    assert_equal 317, receipt.total
    assert_equal [ "85627834", "徠樂企業社" ], [ receipt.seller_tax_id, receipt.seller_name ]
    assert_equal [ [ "魔術靈馬桶清潔劑 高密泡/殺菌瞬潔/雙重凈力, 1個, 超解垢漂潔馬桶清潔劑 500ml, 500ml", 2, 60, 120 ], [ "運費", 2, 98.5, 197 ] ],
                 receipt.items.map { [ it.text, it.quantity.to_i, it.unit_price.to_f, it.amount.to_i ] }
  end

  test "the same page split into single words (other PDF tools): words on a line keep their spaces" do
    words = [ word("85627834", 40.6, 89.6, 44.4, 10), word("徠樂企業社", 87.3, 89.6, 50, 10), word("HX45765353", 49.8, 164, 51.7), word("2026/11/02", 126.1, 164, 47),
              word("品名", 100.7, 192, 18), word("稅別", 191.8, 192, 18), word("數量", 240.1, 192, 18), word("單價", 297, 192, 18), word("金額", 365.3, 192, 18),
              word("清潔劑", 67.1, 230.5, 27), word("500ml,", 96.1, 230.5, 28.4), word("500ml", 126.5, 230.5, 25.9),
              word("應稅", 191.8, 221.5, 18), word("2", 246.6, 221.5, 5), word("60", 301, 221.5, 10), word("120", 366.8, 221.5, 15),
              word("總計", 217.4, 279, 18), word("發票總金額", 173.7, 360.5, 45), word("120", 309.9, 360.5, 15) ]
    receipt = Supplies::InvoicePdfParser.call(words)
    assert_equal [ [ "清潔劑 500ml, 500ml", 2, 120 ] ], receipt.items.map { [ it.text, it.quantity.to_i, it.amount.to_i ] }
    assert_equal 120, receipt.total
  end

  test "another layout: ROC date, no 品名 heading, no unit price column, a discount line dropped" do
    words = [ word("統一編號：12345678", 40, 40, 120), word("發票號碼 AB-12345678", 40, 60, 120), word("115/11/08", 200, 60, 45),
              word("商品", 40, 100, 18), word("數量", 200, 100, 18), word("小計", 260, 100, 18),
              word("衛生紙", 40, 120, 27), word("2", 206, 120, 5), word("578", 262, 120, 15),
              word("折扣", 40, 135, 18), word("1", 206, 135, 5), word("-50", 262, 135, 15),
              word("合計", 40, 170, 18), word("528", 262, 170, 15) ]
    receipt = Supplies::InvoicePdfParser.call(words)
    assert_equal [ "AB12345678", Date.new(2026, 11, 8), 528, "12345678" ], [ receipt.invoice_no, receipt.issued_on, receipt.total, receipt.seller_tax_id ]
    assert_equal [ [ "衛生紙", 2, 289 ] ], receipt.items.map { [ it.text, it.quantity.to_i, it.unit_price.to_i ] }
  end

  test "no item table: total only; no invoice number, date or text: not an invoice" do
    receipt = Supplies::InvoicePdfParser.call([ word("AB12345678", 40, 40), word("2026/11/08", 140, 40), word("總計", 40, 80), word("812", 100, 80) ])
    assert_equal [ 812, [] ], [ receipt.total, receipt.items ]

    [ [], [ word("Hello", 10, 10) ], [ word("AB12345678", 40, 40), word("總計", 40, 80), word("812", 100, 80) ], "not json", { "s" => "x" } ].each do |input|
      assert_raises(Supplies::InvoicePdfParser::Invalid, input.inspect) { Supplies::InvoicePdfParser.call(input) }
    end
  end
end
