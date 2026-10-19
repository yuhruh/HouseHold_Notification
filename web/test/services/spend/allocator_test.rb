require "test_helper"

class Spend::AllocatorTest < ActiveSupport::TestCase
  def split(year, month, amount, currency = "TWD")
    Spend::Allocator.call(Period.parse(year, month), BigDecimal(amount.to_s), currency).map { |p| [ p.year, p.month, p.amount ] }
  end

  test "the PRD examples" do
    assert_equal [ [ 2026, 1, 290 ], [ 2026, 2, 290 ] ], split(2026, "1月-2月", 580)
    full = split(2026, "全年", 48_005)
    assert_equal [ 4000 ] * 11 + [ 4005 ], full.map(&:last)
    assert_equal BigDecimal("48005"), full.sum(&:last)
    assert_equal %w[33.33 33.33 33.34], split(2026, "3月-5月", "100.00", "USD").map { |_, _, a| a.to_s("F") }
    assert_equal [ [ 2025, 12 ], [ 2026, 1 ] ], split(2025, "12月-1月", 580).map { |y, m, _| [ y, m ] }
  end
end
