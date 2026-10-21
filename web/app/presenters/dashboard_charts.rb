# ECharts options for the dashboard (PRD §8). Every data point carries the filters its drill-down
# uses (`filters`), and box plot outliers carry their record_id, so clicks map back to records.
class DashboardCharts
  COLORS = { "expense" => "#2563eb", "maintenance" => "#16a34a", "tax" => "#d97706" }.freeze
  YEAR_COLORS = [ "#f59e0b", "#2563eb", "#9ca3af", "#16a34a", "#7c3aed" ].freeze

  def initialize(query, utility_query:)
    @q, @utility = query, utility_query
  end

  # X-axis labels: months, or years when all years are shown
  def labels(query = @q) = query.all_years? ? query.buckets.map(&:to_s) : (1..12).map { |m| I18n.t("records.month", month: m) }

  def monthly
    series = @q.monthly_by_type.map do |type, values|
      { name: I18n.t("records.types.#{type}"), type: "bar", stack: "spend", itemStyle: { color: COLORS[type] },
        data: values.zip(@q.buckets).map { |v, b| point(v, @q, **@q.bucket_filter(b), record_type: type) } }
    end
    base(legend: true).merge(xAxis: { type: "category", data: labels }, yAxis: { type: "value" }, series:)
  end

  def utilities
    series = @utility.utility_trend.map do |category, values|
      { name: category.name, type: "line", smooth: true,
        data: values.zip(@utility.buckets).map { |v, b| point(v, @utility, **@utility.bucket_filter(b), category_id: category.id, record_type: nil) } }
    end
    base(legend: true).merge(xAxis: { type: "category", data: labels(@utility) }, yAxis: { type: "value" }, series:)
  end

  def categories
    rows = @q.by_category
    base.merge(xAxis: { type: "value" }, yAxis: { type: "category", data: rows.map { |c, _| c.name }.reverse, axisLabel: { width: 90, overflow: "truncate" } },
      grid: { left: 100, right: 24, top: 16, bottom: 24 },
      series: [ { type: "bar", data: rows.reverse.map { |c, v| point(v, @q, category_id: c.id) } } ])
  end

  def payment_methods
    rows = @q.by_payment_method
    base(tooltip: { trigger: "item" }).merge(series: [ { type: "pie", radius: [ "35%", "70%" ],
      data: rows.map { |pm, v| point(v, @q, payment_method_id: pm&.id || "none").merge(name: pm&.name || I18n.t("dashboards.show.no_payment_method")) } } ])
  end

  def boxplot
    groups = @q.box_groups
    names = groups.map { |g| g[:category].name }
    boxes = groups.map.with_index do |g, i|
      next { value: [], filters: drill(@q, category_id: g[:category].id, box: 1) } unless g[:stats]
      { value: g[:stats][:box].map { |v| v.to_f.round(2) }, filters: drill(@q, category_id: g[:category].id, box: 1) }
    end
    # Outliers of a box are red; bills of categories too small for a box are plain grey points
    point = ->(r, i, color) { { value: [ i, r.amount_paid.to_f ], record_id: r.id, name: r.title, itemStyle: { color: } } }
    points = groups.each_with_index.flat_map do |g, i|
      g[:outliers].map { |r| point.(r, i, g[:stats] ? "#dc2626" : "#6b7280") }
    end
    base(tooltip: { trigger: "item" }).merge(xAxis: { type: "category", data: names, axisLabel: { interval: 0, rotate: 30 } },
      yAxis: { type: "value" }, grid: { left: 56, right: 16, top: 16, bottom: 72 },
      series: [ { name: I18n.t("dashboards.show.box"), type: "boxplot", data: boxes },
                { name: I18n.t("dashboards.show.points"), type: "scatter", data: points } ])
  end

  # Bills by billing cycle, A: one bar per period oldest first, a gap where no bill covers the months,
  # and a dashed average line (drawn as a line series: the ECharts build has no markLine)
  def cycle_timeline(cycles)
    paid = cycles.filter_map(&:amount)
    average = paid.empty? ? nil : (paid.sum / paid.size).round(2).to_f
    bars = cycles.map do |c|
      next { value: nil } unless c.amount
      { value: c.amount.to_f.round(2), record_id: (c.records.first.id if c.records.one?) }.compact
    end
    base(legend: true).merge(xAxis: { type: "category", data: cycles.map { |c| cycle_label(c) }, axisLabel: { interval: 0, rotate: 30 } },
      yAxis: { type: "value" }, grid: { left: 56, right: 16, top: 40, bottom: 72 },
      series: [ { name: I18n.t("dashboards.show.amount"), type: "bar", data: bars, itemStyle: { color: COLORS["expense"] } },
                { name: I18n.t("dashboards.show.average"), type: "line", symbol: "none", data: [ average ] * cycles.size,
                  lineStyle: { type: "dashed", color: "#6b7280" }, itemStyle: { color: "#6b7280" } } ])
  end

  # Bills by billing cycle, B: the same months side by side, one bar per year (newest orange, then
  # blue, then grey). {cycles: ["1月-2月", …], years: {2025 => [amount or nil per cycle]}}
  def cycle_years(cycles)
    keys = cycles.map { |c| [ c.period.start_month, c.period.end_month ] }.uniq.sort
    years = cycles.map { |c| c.period.start_year }.uniq.sort
    { cycles: keys.map { |s, e| months_label(s, e) },
      years: years.index_with { |y| keys.map { |k| cycles.find { |c| c.period.start_year == y && [ c.period.start_month, c.period.end_month ] == k } } } }
  end

  def cycle_yoy(cycles)
    table = cycle_years(cycles)
    series = table[:years].to_a.reverse.each_with_index.map do |(year, list), i|
      { name: year.to_s, type: "bar", itemStyle: { color: YEAR_COLORS[i] || YEAR_COLORS.last },
        data: list.map { |c| c ? { value: c.amount.to_f.round(2), record_id: (c.records.first.id if c.records.one?) }.compact : { value: nil } } }
    end.reverse
    base(legend: true).merge(xAxis: { type: "category", data: table[:cycles] }, yAxis: { type: "value" }, series:)
  end

  # "View as table" for A: each period with its amount and the change from the previous paid bill
  def cycle_timeline_table(cycles)
    previous = nil
    rows = cycles.map do |c|
      row = [ cycle_label(c), [ c.amount || "–", change(previous, c.amount) ] ]
      previous = c.amount if c.amount
      row
    end
    { columns: [ I18n.t("dashboards.show.amount"), I18n.t("dashboards.show.change") ], rows: }
  end

  # "View as table" for B: one row per year, plus each cycle's change between its latest two years
  def cycle_yoy_table(cycles)
    table = cycle_years(cycles)
    amounts = table[:years].transform_values { |list| list.map { |c| c&.amount } }
    rows = amounts.map { |year, list| [ year.to_s, list.map { |v| v || "–" } ] }
    rows << [ I18n.t("dashboards.show.change"), amounts.values.transpose.map { |column| change(*column.compact.last(2).then { |l| l.size == 2 ? l : [ nil, nil ] }) } ] if amounts.size > 1
    { columns: table[:cycles], rows: }
  end

  def cycle_label(cycle) = "#{cycle.period.start_year} #{months_label(cycle.period.start_month, cycle.period.end_month)}#{cycle.amount ? "" : " #{I18n.t("dashboards.show.missing")}"}"

  private

  def change(before, now)
    return "–" unless before && now && before.positive?
    percent = ((now - before) / before * 100).round
    "#{'+' if percent.positive?}#{percent}%"
  end

  def months_label(start_month, end_month)
    return I18n.t("dashboards.show.full_year") if start_month == 1 && end_month == 12
    start_month == end_month ? "#{start_month}月" : "#{start_month}月-#{end_month}月"
  end

  def point(value, query, **filters) = { value: value.to_f.round(2), filters: drill(query, **filters) }

  def drill(query, **filters)
    { mode: query.mode, year: query.year, currency: query.currency, record_type: query.record_type }.merge(filters).compact
  end

  def base(legend: false, tooltip: { trigger: "axis" })
    { tooltip:, grid: { left: 56, right: 16, top: legend ? 40 : 16, bottom: 32 }, legend: (legend ? { top: 0 } : nil) }.compact
  end
end
