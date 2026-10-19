require "test_helper"

class StatsTest < ActiveSupport::TestCase
  test "quartiles match Excel QUARTILE.INC and outliers lie beyond 1.5 × IQR" do
    values = (1..10).map { |v| BigDecimal(v) }
    assert_equal [ 3.25, 5.5, 7.75 ], [ 0.25, 0.5, 0.75 ].map { |q| Stats.quartile(values, q).to_f }
    result = Stats.box(values + [ BigDecimal(40) ])
    assert_equal [ BigDecimal(40) ], result[:outliers]
    assert_equal BigDecimal(10), result[:box].last
  end
end
