require "test_helper"

class PeriodTest < ActiveSupport::TestCase
  test "parses ranges, single months and full year" do
    assert_equal [ 2025, 1, 2025, 2 ], Period.parse(2025, "1月-2月").deconstruct
    assert_equal [ 2025, 7, 2025, 7 ], Period.parse("2025", "7月").deconstruct
    assert_equal [ 2026, 1, 2026, 12 ], Period.parse(2026, "全年").deconstruct
    assert_equal [ 2025, 1, 2025, 2 ], Period.parse(2025, "１月–２月").deconstruct
  end

  test "end year is year + 1 when the end month is before the start month" do
    period = Period.parse(2025, "12月-1月")
    assert_equal [ 2025, 12, 2026, 1 ], period.deconstruct
    assert_equal 2, period.month_count
    assert_equal 2025, Period.parse(2025, "1月-2月").end_year
  end

  test "rejects unknown text and out-of-range months" do
    assert_raises(Period::ParseError) { Period.parse(2025, "1–2月?") }
    assert_raises(Period::ParseError) { Period.parse(2025, "13月") }
    assert_raises(Period::ParseError) { Period.parse("abc", "1月") }
  end
end
