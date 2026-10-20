# ECharts options for the dashboard (PRD §8). Every data point carries the filters its drill-down
# uses (`filters`), and box plot outliers carry their record_id, so clicks map back to records.
class DashboardCharts
  COLORS = { "expense" => "#2563eb", "maintenance" => "#16a34a", "tax" => "#d97706" }.freeze

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

  private

  def point(value, query, **filters) = { value: value.to_f.round(2), filters: drill(query, **filters) }

  def drill(query, **filters)
    { mode: query.mode, year: query.year, currency: query.currency, record_type: query.record_type }.merge(filters).compact
  end

  def base(legend: false, tooltip: { trigger: "axis" })
    { tooltip:, grid: { left: 56, right: 16, top: legend ? 40 : 16, bottom: 32 }, legend: (legend ? { top: 0 } : nil) }.compact
  end
end
