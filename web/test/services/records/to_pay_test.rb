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

  test "a period that's due but ambiguous isn't shown as scheduled" do
    template = @home.recurring_templates.create!(category: @ac, interval_months: 2, starts_on: Date.new(2026, 11, 1), lead_days: 7)
    2.times { @home.records.create!(record_type: "maintenance", category: @ac, period: Period.parse(2026, "11月-12月")) }
    assert_equal "2027 1月-2月", to_pay(Date.new(2026, 11, 14)).scheduled.sole.period.to_s
    assert_equal 1, template.ambiguous_periods(Date.new(2026, 11, 14)).size
  end
end
