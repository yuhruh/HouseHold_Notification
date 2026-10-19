require "test_helper"

class RecurringTemplateTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
  end

  def template(name, **attrs)
    @home.recurring_templates.new({ category: @home.categories.find_by!(name_zh: name), interval_months: 2,
      starts_on: Date.new(2026, 1, 1) }.merge(attrs))
  end

  test "periods start in the anchor month and repeat every interval, crossing the year" do
    t = template("水費", anchor_month: 11)
    t.validate
    assert_equal [ "2025 11月-12月", "2026 1月-2月", "2026 3月-4月" ], t.periods_from(Date.new(2025, 11, 1)).first(3).map(&:to_s)
    assert_equal [ 2026, 1 ], t.periods_from(Date.new(2025, 12, 15)).first.deconstruct.first(2)
    yearly = template("社區管理費", interval_months: 12, anchor_month: 12, period_span_months: 2)
    assert_equal [ 2026, 12, 2027, 1 ], yearly.periods_from(Date.new(2026, 6, 1)).first.deconstruct
  end

  test "the due date is due_day in the month due_month_offset after the period starts, clamped to month end" do
    t = template("水費", due_day: 31, due_month_offset: 1)
    t.validate
    period = t.periods_from(Date.new(2026, 1, 1)).first
    assert_equal Date.new(2026, 2, 28), t.due_on_for(period)
    assert_equal Date.new(2026, 2, 21), t.generation_date(period), "7 lead days before the due date"
    t.due_day = nil
    assert_equal Date.new(2025, 12, 25), t.generation_date(period), "without a due day: before the period starts"
  end

  test "title, type, span and anchor default from the category, interval and start date" do
    t = template("房屋稅", interval_months: 12, starts_on: Date.new(2026, 5, 1))
    t.validate
    assert_equal [ "房屋稅", "tax", 12, 5 ], [ t.title, t.record_type, t.period_span_months, t.anchor_month ]
  end

  test "a fixed amount is required, and 牌照稅 needs its plate number" do
    assert_not template("社區管理費", amount_fixed: true).valid?
    t = template("牌照稅", interval_months: 12)
    assert_not t.valid?
    assert_includes t.errors.details[:details], { error: :required_for_category, label: "車牌號碼", category: "牌照稅" }
  end
end
