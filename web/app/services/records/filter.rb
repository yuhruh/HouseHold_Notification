module Records
  # The records list (PRD §2): filters and the summary bar. Year/month select records whose billing
  # period overlaps; the summary sums the full Required / Paid / Outstanding of the rows shown, per
  # type and currency. Only `overdue` depends on today, bound as a parameter.
  class Filter
    # "outstanding" = the rows behind the summary's Outstanding column: not settled, with an amount due
    STATUSES = %w[unpaid partial overdue paid outstanding].freeze
    CURRENCIES = %w[TWD USD].freeze
    KEYS = %i[year month type category_id status payment_method_id currency q].freeze

    Total = Data.define(:record_type, :currency, :required, :paid, :outstanding)

    attr_reader :params

    def initialize(household, params, today: Date.current)
      @household = household
      @params = params.to_h.symbolize_keys.slice(*KEYS).compact_blank
      @today = today
    end

    # Not fully paid first (unpaid, partial, overdue), then paid; each group newest billing period first
    def records
      @records ||= scope.includes(:category, :payment_method)
        .order(settled: :asc, period_year: :desc, period_start_month: :desc, record_no: :desc)
    end

    def summary
      scope.group(:record_type, :currency).order(:record_type, :currency).pluck(
        :record_type, :currency, Arel.sql("COALESCE(SUM(amount_required), 0)"), Arel.sql("COALESCE(SUM(amount_paid), 0)"),
        Arel.sql("COALESCE(SUM(CASE WHEN settled = false AND amount_required IS NOT NULL THEN amount_required - COALESCE(amount_paid, 0) ELSE 0 END), 0)")
      ).map { |row| Total.new(*row) }
    end

    # Overall totals per currency (TWD and USD are never added together)
    def totals
      summary.group_by(&:currency).map do |currency, rows|
        Total.new(nil, currency, rows.sum(&:required), rows.sum(&:paid), rows.sum(&:outstanding))
      end
    end

    def years
      ([ @today.year ] + @household.records.distinct.pluck(:period_year, :period_end_year).flatten).uniq.sort.reverse
    end

    def active? = params.any?

    private

    def scope
      relation = @household.records
      if (year = params[:year].to_i).positive?
        month = params[:month].to_i
        relation = (1..12).cover?(month) ? relation.overlapping(year * 12 + month, year * 12 + month) : relation.overlapping(year * 12 + 1, year * 12 + 12)
      end
      relation = relation.where(record_type: params[:type]) if Category::RECORD_TYPES.value?(params[:type])
      relation = relation.where(category_id: params[:category_id]) if params[:category_id]
      relation = relation.where(payment_method_id: params[:payment_method_id]) if params[:payment_method_id]
      relation = relation.where(currency: params[:currency]) if CURRENCIES.include?(params[:currency])
      relation = with_status(relation, params[:status]) if STATUSES.include?(params[:status])
      if params[:q]
        like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        relation = relation.where("title ILIKE :like OR details ILIKE :like OR payment_note ILIKE :like", like:)
      end
      relation
    end

    def with_status(relation, status)
      return relation.where(settled: true) if status == "paid"
      return relation.where(settled: false).where.not(amount_required: nil) if status == "outstanding"

      unsettled = relation.where(settled: false)
      return unsettled.where(due_on: ...@today) if status == "overdue"

      not_overdue = unsettled.where("due_on IS NULL OR due_on >= ?", @today)
      partial = "paid_on IS NOT NULL AND amount_paid IS NOT NULL AND amount_required IS NOT NULL AND amount_paid < amount_required"
      status == "partial" ? not_overdue.where(partial) : not_overdue.where.not(partial)
    end
  end
end
