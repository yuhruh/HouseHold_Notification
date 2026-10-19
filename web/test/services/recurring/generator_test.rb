require "test_helper"

class Recurring::GeneratorTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
  end

  def water_template(**attrs)
    @home.recurring_templates.create!({ category: @water, interval_months: 2, anchor_month: 1, starts_on: Date.new(2026, 1, 1),
      due_day: 15, due_month_offset: 2, lead_days: 7, default_amount: 580 }.merge(attrs))
  end

  def generate(template, today) = Recurring::Generator.call(template, today:)

  test "creates every period whose generation date has come, once; variable bills start without an amount" do
    t = water_template
    result = generate(t, Date.new(2026, 5, 10)) # 1月-2月 due 3/15 (made 3/8), 3月-4月 due 5/15 (made 5/8)
    assert_equal [ "2026 1月-2月", "2026 3月-4月" ], result.created.map { |r| r.period.to_s }
    bill = result.created.first
    assert_equal [ Date.new(2026, 3, 15), nil, "水費", t ], [ bill.due_on, bill.amount_required, bill.title, bill.recurring_template ]
    assert_empty generate(t, Date.new(2026, 5, 10)).created, "a second run creates nothing"
    assert_equal 1, generate(t, Date.new(2026, 7, 9)).created.size, "catch-up after a missed day"
  end

  test "fixed amounts are copied; no back-fill before starts_on" do
    t = water_template(amount_fixed: true, starts_on: Date.new(2026, 3, 1))
    result = generate(t, Date.new(2026, 5, 10))
    assert_equal [ "2026 3月-4月" ], result.created.map { |r| r.period.to_s }
    assert_equal BigDecimal("580"), result.created.first.amount_required
  end

  test "an existing bill for the period is linked instead of duplicated; two matches link none" do
    imported = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月"), amount_required: 600)
    result = generate(water_template, Date.new(2026, 3, 10))
    assert_equal [ imported ], result.linked
    assert_empty result.created

    t2 = water_template(details: "B 棟")
    2.times { @home.records.create!(record_type: "expense", category: @water, details: "B 棟", period: Period.parse(2026, "1月-2月")) }
    result = generate(t2, Date.new(2026, 3, 10))
    assert_empty result.created
    assert_equal 1, result.ambiguous.size
    assert_equal 1, t2.ambiguous_periods(Date.new(2026, 3, 10)).size
  end

  test "without a due day, the template's reminder frequency is copied onto the bill" do
    t = water_template(due_day: nil, default_reminder_frequency: "weekly")
    bill = generate(t, Date.new(2025, 12, 26)).created.sole
    assert_equal [ nil, "weekly", Date.new(2025, 12, 27) ], [ bill.due_on, bill.reminder_frequency, bill.reminder_starts_on ]
  end

  test "the daily job generates in the owner's time zone" do
    users(:alex).update!(time_zone: "Pacific/Pago_Pago") # UTC−11
    t = water_template
    travel_to Time.utc(2026, 3, 8, 5) do # 3/8 in UTC, still 3/7 in Pago Pago
      GenerateRecurringRecordsJob.perform_now
      assert_empty t.records
    end
    travel_to Time.utc(2026, 3, 8, 12) do
      GenerateRecurringRecordsJob.perform_now
      assert_equal 1, t.records.count
    end
  end
end
