# Every dashboard number and its drill-down come from here (PRD §8, Business rules), so a clicked
# value and the records listed under it can't disagree. Spend = amount_paid of records with a paid
# date. Mode "paid" counts the full amount in the month of paid_on; mode "period" splits it across
# the billing period with Spend::Allocator. TWD and USD are never added together.
class DashboardQuery
  MODES = %w[paid period].freeze
  UTILITIES = %w[水費 電費 瓦斯費].freeze
  BOX_MIN = 5

  Piece = Data.define(:record, :year, :month, :amount)

  attr_reader :household, :mode, :year, :currency, :record_type

  def initialize(household, mode: "paid", year:, currency:, record_type: nil)
    @household = household
    @mode = MODES.include?(mode.to_s) ? mode.to_s : "paid"
    @year = year.to_i
    @currency = Household::CURRENCIES.include?(currency) ? currency : household.default_currency
    @record_type = Category::RECORD_TYPES.value?(record_type) ? record_type : nil
  end

  def with(**changes)
    self.class.new(household, mode:, year:, currency:, record_type:, **changes)
  end

  # Spend pieces in the selected year, optionally narrowed (month, record_type, category, payment method)
  def pieces(month: nil, category_id: nil, payment_method_id: nil, record_type: self.record_type)
    all_pieces.select do |p|
      p.year == year && (month.nil? || p.month == month.to_i) &&
        (record_type.nil? || p.record.record_type == record_type) &&
        (category_id.nil? || p.record.category_id == category_id.to_i) &&
        (payment_method_id.nil? || p.record.payment_method_id == (payment_method_id.to_s == "none" ? nil : payment_method_id.to_i))
    end
  end

  def total(**filters) = pieces(**filters).sum(&:amount)

  # Monthly spend stacked by type: {record_type => [12 sums]}
  def monthly_by_type
    types = record_type ? [ record_type ] : Category::RECORD_TYPES.values
    types.index_with { |type| (1..12).map { |m| total(month: m, record_type: type) } }
  end

  # Utility lines: {category => [12 sums]} for the 水/電/瓦斯 categories that exist
  def utility_trend
    household.categories.where(record_type: "expense", name_zh: UTILITIES).to_a.sort_by { |c| UTILITIES.index(c.name_zh) }
      .index_with { |c| (1..12).map { |m| total(month: m, category_id: c.id, record_type: nil) } }
  end

  def by_category
    pieces.group_by { |p| p.record.category }.transform_values { |list| list.sum(&:amount) }.sort_by { |_, v| -v }
  end

  def by_payment_method
    pieces.group_by { |p| p.record.payment_method }.transform_values { |list| list.sum(&:amount) }.sort_by { |_, v| -v }
  end

  # One point per record (full amount_paid, not split), per category, for records counted this year
  def box_groups
    records = pieces.map(&:record).uniq
    records.group_by(&:category).sort_by { |c, _| [ c.record_type, c.position, c.id ] }.map do |category, list|
      values = list.map(&:amount_paid)
      stats = list.size >= BOX_MIN ? Stats.box(values) : nil
      outliers = stats ? list.select { |r| stats[:outliers].include?(r.amount_paid.to_d) } : list
      { category:, records: list.sort_by(&:amount_paid), stats:, outliers: }
    end
  end

  def years
    paid = household.records.where(currency:).where.not(paid_on: nil)
    ([ Date.current.year, year ] + paid.distinct.pluck(Arel.sql("EXTRACT(YEAR FROM paid_on)::int")) +
      paid.distinct.pluck(:period_year, :period_end_year).flatten).uniq.sort.reverse
  end

  # Unpaid now, in the viewer's today
  def unpaid_counts(today: Date.current)
    unsettled = household.records.where(settled: false, currency:)
    { unpaid: unsettled.count, overdue: unsettled.where(due_on: ...today).count }
  end

  # Drill-down rows: each record with the amount it contributes under the same filters
  def drilldown(**filters)
    pieces(**filters).group_by(&:record).map { |record, list| [ record, list.sum(&:amount) ] }
      .sort_by { |record, _| [ record.paid_on, record.id ] }
  end

  private

  def all_pieces
    @all_pieces ||= paid_records.flat_map do |record|
      if mode == "paid"
        [ Piece.new(record:, year: record.paid_on.year, month: record.paid_on.month, amount: record.amount_paid.to_d) ]
      else
        Spend::Allocator.call(record.period, record.amount_paid, record.currency).map do |part|
          Piece.new(record:, year: part.year, month: part.month, amount: part.amount)
        end
      end
    end
  end

  # Records that touch the year by paid date or by billing period (hundreds of rows at most)
  def paid_records
    scope = household.records.where(currency:).where.not(paid_on: nil).where.not(amount_paid: nil)
      .includes(:category, :payment_method)
    if mode == "paid"
      scope.where(paid_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
    else
      scope.overlapping(year * 12 + 1, year * 12 + 12)
    end
  end
end
