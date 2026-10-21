require "test_helper"

class DashboardQueryTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @power = @home.categories.find_by!(name_zh: "電費")
    @fee = @home.categories.find_by!(name_zh: "社區管理費")
    @card = @home.payment_methods.create!(name: "玉山 ubear", kind: "card")
    paid(@water, "1月-2月", 580, Date.new(2026, 4, 14), payment_method: @card)
    paid(@water, "12月-1月", 600, Date.new(2026, 2, 15), year: 2025)
    paid(@fee, "全年", 48_005, Date.new(2026, 1, 28), payment_method: @card)
    [ 900, 950, 1000, 1050, 1100, 5000 ].each_with_index { |a, i| paid(@power, "#{i + 1}月", a, Date.new(2026, i + 2, 3)) }
    paid(@power, "3月", 70, Date.new(2026, 4, 1), currency: "USD")
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "5月-6月"), amount_required: 610) # unpaid: no spend
  end

  def paid(category, months, amount, paid_on, year: 2026, currency: "TWD", payment_method: nil)
    @home.records.create!(record_type: category.record_type, category:, period: Period.parse(year, months), currency:,
      amount_required: amount, amount_paid: amount, paid_on:, payment_method:)
  end

  def query(mode, currency: "TWD", year: 2026) = DashboardQuery.new(@home, mode:, year:, currency:)

  test "paid-date totals equal SQL sums per currency; unpaid bills aren't spend" do
    assert_equal @home.records.where(currency: "TWD").where(paid_on: Date.new(2026, 1, 1)..Date.new(2026, 12, 31)).sum(:amount_paid), query("paid").total
    assert_equal BigDecimal("70"), query("paid", currency: "USD").total
    assert_equal BigDecimal("580"), query("paid").total(month: 4, category_id: @water.id)
  end

  test "billing-period mode splits across months and years" do
    q = query("period")
    assert_equal BigDecimal("300") + BigDecimal("290"), q.total(month: 1, category_id: @water.id), "600 over 12月–1月 gives Jan 300; 580 over 1–2 gives Jan 290"
    assert_equal BigDecimal("4005"), q.total(month: 12, category_id: @fee.id)
  end

  test "all years: totals cover every year, and the monthly charts get one bucket per year" do
    q = query("paid", year: DashboardQuery::ALL)
    assert q.all_years?
    assert_equal @home.records.where(currency: "TWD").where.not(paid_on: nil).sum(:amount_paid), q.total
    assert_equal [ 2026 ], q.buckets, "every TWD bill was paid in 2026"
    assert_equal [ q.total ], q.monthly_by_type.values.transpose.map(&:sum)

    period = query("period", year: DashboardQuery::ALL)
    assert_equal [ 2025, 2026 ], period.buckets, "12月-1月 2025 puts half of the 600 in 2025"
    assert_equal BigDecimal("300"), period.total(year: 2025)
    assert_equal q.total, period.total, "splitting by period moves spend between years, never changes the sum"
    assert_equal %w[2025 2026], DashboardCharts.new(period, utility_query: period).labels
  end

  test "every chart point's drill-down total equals its value, in both modes, for a year and all years" do
    DashboardQuery::MODES.product([ 2026, DashboardQuery::ALL ]).each do |mode, year|
      q = query(mode, year:)
      charts = DashboardCharts.new(q, utility_query: q.with(record_type: nil))
      points = [ charts.monthly, charts.utilities, charts.categories, charts.payment_methods ]
        .flat_map { |option| option[:series].flat_map { |s| s[:data] } }
      assert points.size > (q.all_years? ? 5 : 30)
      points.each do |point|
        filters = point[:filters].symbolize_keys
        drill = DashboardQuery.new(@home, mode: filters[:mode], year: filters[:year], currency: filters[:currency], record_type: filters[:record_type])
        rows = drill.drilldown(**filters.slice(:month, :category_id, :payment_method_id))
        assert_equal point[:value], rows.sum { |_, amount| amount }.to_f.round(2), "#{mode} #{year} #{filters}"
      end
    end
  end

  test "the box plot has a box for 5+ bills, outliers carry their record, small groups are points" do
    option = DashboardCharts.new(query("paid"), utility_query: query("period")).boxplot
    names = option[:xAxis][:data]
    power = option[:series][0][:data][names.index("電費")]
    assert_equal [ 962.5, 1025.0, 1087.5 ], power[:value][1..3], "QUARTILE.INC over all six bills"
    assert_equal 1100.0, power[:value][4], "the whisker stops at the last value inside 1.5 × IQR"
    outlier = option[:series][1][:data].find { |p| p[:value] == [ names.index("電費"), 5000.0 ] }
    assert_equal @home.records.find_by!(amount_paid: 5000).id, outlier[:record_id]
    assert_empty option[:series][0][:data][names.index("水費")][:value], "水費 has fewer than 5 bills: points only"
  end

  test "bills by billing cycle: one bar per period (not split), a gap where no bill covers the months, year against year by period" do
    @home.records.where(category: @water).delete_all
    { [ 2024, "9月-10月" ] => 538, [ 2025, "1月-2月" ] => 532, [ 2025, "3月-4月" ] => 573, [ 2025, "9月-10月" ] => 654,
      [ 2026, "1月-2月" ] => 624, [ 2026, "3月-4月" ] => 667 }.each { |(year, months), amount| paid(@water, months, amount, Date.new(2026, 5, 1), year:) }
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "5月-6月"), amount_required: 580) # unpaid: left out
    q = query("paid", year: 2025) # the year filter and mode don't apply

    assert_equal [ 538, 532, 573, 654, 624, 667 ], q.cycles(@water).map { |c| c.amount.to_i }
    timeline = q.cycles(@water, gaps: true)
    charts = DashboardCharts.new(q, utility_query: q)
    assert_equal [ "2024 9月-10月", "2024 11月-12月 （缺）", "2025 1月-2月", "2025 3月-4月", "2025 5月-8月 （缺）", "2025 9月-10月", "2025 11月-12月 （缺）", "2026 1月-2月", "2026 3月-4月" ],
      timeline.map { |c| charts.cycle_label(c) }
    option = charts.cycle_timeline(timeline)
    assert_equal [ 538.0, nil, 532.0, 573.0, nil, 654.0, nil, 624.0, 667.0 ], option[:series][0][:data].map { |d| d[:value] }
    assert_equal [ 598.0 ] * 9, option[:series][1][:data], "average of the paid bills: 3588 / 6"
    assert option[:series][0][:data].first[:record_id], "a bar opens its record"
    assert_equal [ "–", "–", "-1%", "+8%", "–", "+14%", "–", "-5%", "+7%" ], charts.cycle_timeline_table(timeline)[:rows].map { |_, (_, change)| change }

    yoy = charts.cycle_yoy(q.cycles(@water))
    assert_equal [ "1月-2月", "3月-4月", "9月-10月" ], yoy[:xAxis][:data]
    assert_equal %w[2024 2025 2026], yoy[:series].map { |s| s[:name] }
    assert_equal [ nil, nil, 538.0 ], yoy[:series][0][:data].map { |d| d[:value] }
    assert_equal "#f59e0b", yoy[:series].last[:itemStyle][:color], "the newest year is orange"
    assert_equal [ "+17%", "+16%", "+22%" ], charts.cycle_yoy_table(q.cycles(@water))[:rows].last.last, "each cycle's latest two years: 9月-10月 is 2025 vs 2024"
  end
end
