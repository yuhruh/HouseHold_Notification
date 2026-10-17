require "test_helper"

class SheetImport::AmountParserTest < ActiveSupport::TestCase
  def parse(text) = SheetImport::AmountParser.parse(text)

  test "accepts Sheets display strings" do
    assert_equal [ BigDecimal("1234"), "TWD" ], parse("NT$1,234")
    assert_equal [ BigDecimal("1234"), "TWD" ], parse("NT$ 1,234.00")
    assert_equal [ BigDecimal("1234"), nil ], parse("１，２３４")
    assert_equal [ BigDecimal("1234"), nil ], parse("$1,234")
    assert_equal [ BigDecimal("12.5"), "USD" ], parse("US$12.50")
    assert_equal [ nil, nil ], parse("-")
    assert_equal [ nil, nil ], parse("")
  end

  test "rejects negatives and non-numbers" do
    [ "(1,234)", "-1234", "約1200", "1.234,00" ].each do |text|
      assert_raises(SheetImport::AmountParser::ParseError, text) { parse(text) }
    end
  end
end
