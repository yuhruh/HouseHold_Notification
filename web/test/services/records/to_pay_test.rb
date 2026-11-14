require "test_helper"

class Records::ToPayTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @ac = @home.categories.find_by!(name_zh: "冷氣清洗")
  end

  def to_pay(today) = Records::ToPay.new(@home, today:)

  test "a recurring bill's next period shows as scheduled until it's generated, without being counted" do
    done = @home.records.create!(record_type: "maintenance", category: @ac, details: "客廳", period: Period.parse(2026, "11月"),
      paid_on: Date.new(2026, 11, 3))
    template = @home.recurring_templates.create!(RecurringTemplate.attributes_from(done).merge(interval_months: 2, period_span_months: 1))
    Recurring::Generator.call(template, today: Date.new(2026, 11, 14))
    assert_equal template, done.reload.recurring_template, "the record it was made from is its first bill"

    list = to_pay(Date.new(2026, 11, 14))
    scheduled = list.scheduled.sole
    assert_equal [ "2027 1月", Date.new(2027, 1, 1), Date.new(2026, 12, 25) ],
      [ scheduled.period.to_s, scheduled.date, scheduled.creates_on ]
    assert_equal 0, list.count, "nothing to pay yet"

    Recurring::Generator.call(template, today: Date.new(2026, 12, 25))
    list = to_pay(Date.new(2026, 12, 25))
    assert_equal "2027 3月", list.scheduled.sole.period.to_s, "then the period after it is scheduled"
    assert_equal [ "冷氣清洗" ], list.soon.map(&:title), "and the generated task is due in the next 30 days"
  end

  test "a bill already waiting to be linked (imported) isn't shown again as scheduled" do
    tax = @home.categories.find_by!(name_zh: "地價稅")
    imported = @home.records.create!(record_type: "tax", category: tax, details: "地價稅", period: Period.parse(2026, "1月-12月"),
      amount_required: 1536, due_on: Date.new(2026, 11, 30))
    @home.recurring_templates.create!(category: tax, details: "地價稅", interval_months: 12, period_span_months: 12,
      starts_on: Date.new(2026, 1, 1), due_day: 30, due_month_offset: 10, lead_days: 7)
    list = to_pay(Date.new(2026, 11, 14))
    assert_equal [ imported ], list.soon, "the imported bill is to pay"
    assert_equal "2027 全年", list.scheduled.sole.period.to_s, "and isn't also shown as 2026's scheduled bill"

    # Planned quarters imported ahead: the next scheduled one is the first quarter without a bill
    %w[1月 4月].each { |m| @home.records.create!(record_type: "maintenance", category: @ac, details: "全戶", period: Period.parse(2027, m)) }
    @home.recurring_templates.create!(category: @ac, details: "全戶", interval_months: 3, period_span_months: 1,
      starts_on: Date.new(2027, 1, 1), lead_days: 7)
    assert_equal [ "2027 7月", "2027 全年" ], to_pay(Date.new(2026, 11, 14)).scheduled.map { it.period.to_s }
  end

  test "a period that's due but ambiguous isn't shown as scheduled" do
    template = @home.recurring_templates.create!(category: @ac, interval_months: 2, starts_on: Date.new(2026, 11, 1), lead_days: 7)
    2.times { @home.records.create!(record_type: "maintenance", category: @ac, period: Period.parse(2026, "11月-12月")) }
    assert_equal "2027 1月-2月", to_pay(Date.new(2026, 11, 14)).scheduled.sole.period.to_s
    assert_equal 1, template.ambiguous_periods(Date.new(2026, 11, 14)).size
  end
end
