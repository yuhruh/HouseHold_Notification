require "test_helper"

class RecordTest < ActiveSupport::TestCase
  setup do
    @household = households(:home)
    Categories::Seed.call(@household)
    @water = @household.categories.find_by!(record_type: "expense", name_zh: "水費")
  end

  def build(**attrs)
    category = attrs.delete(:category) || @water
    @household.records.new({ record_type: category.record_type, category:, title: category.name_zh,
      period: Period.parse(2026, "1月-2月") }.merge(attrs))
  end

  def category(type, name) = @household.categories.find_by!(record_type: type, name_zh: name)

  test "status rules in order: paid, overdue, partial, unpaid" do
    today = Date.new(2026, 4, 20)
    assert_equal :paid, build(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14)).status(today:)
    assert_equal :paid, build(amount_required: 580, amount_paid: 580, paid_on: today, due_on: today - 10).status(today:), "paid after the due date: paid wins"
    assert_equal :overdue, build(amount_required: 580, amount_paid: 300, paid_on: today - 1, due_on: today - 1).status(today:)
    assert_equal :partial, build(amount_required: 580, amount_paid: 300, paid_on: today - 1).status(today:)
    assert_equal :unpaid, build(amount_required: 580).status(today:)
    assert_equal :unpaid, build(amount_required: 580, due_on: today).status(today:), "due today isn't overdue yet"
  end

  test "maintenance is paid with a finished date and blank amounts" do
    ac = category("maintenance", "冷氣清洗")
    assert build(category: ac, paid_on: Date.new(2026, 3, 1)).paid_by_rule?
    assert_not build(category: ac).paid_by_rule?
  end

  test "settled is stored from rule 1 on every save" do
    record = build(amount_required: 580)
    record.save!
    assert_not record.settled
    record.update!(amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    assert record.reload.settled
    record.update!(amount_paid: 300)
    assert_not record.reload.settled, "a partial payment is unsettled"
  end

  test "a payment needs a date, and Paid can't exceed Required" do
    assert_includes build(amount_required: 580, amount_paid: 100).tap(&:validate).errors.details[:paid_on], { error: :required_for_payment }
    assert_includes build(amount_required: 580, amount_paid: 600, paid_on: Date.new(2026, 4, 1)).tap(&:validate).errors.details[:amount_paid], { error: :exceeds_required }
  end

  test "Expense/Tax with a paid date need Required and Paid; Maintenance needs Paid only when Required is set" do
    record = build(paid_on: Date.new(2026, 4, 1)).tap(&:validate)
    assert_includes record.errors.details[:amount_required], { error: :required_with_paid_on }
    assert_includes record.errors.details[:amount_paid], { error: :required_with_paid_on }

    ac = category("maintenance", "冷氣清洗")
    assert build(category: ac, paid_on: Date.new(2026, 4, 1)).valid?
    assert_not build(category: ac, paid_on: Date.new(2026, 4, 1), amount_required: 1500).valid?
  end

  test "牌照稅 and 保險 need details; other categories don't" do
    license = category("tax", "牌照稅")
    record = build(category: license).tap(&:validate)
    assert_equal [ "Details must have the Plate number for Vehicle license tax" ], I18n.with_locale(:en) { record.tap(&:validate).errors.full_messages }
    assert build(category: license, details: "ABC-1234").valid?
    assert build.valid?
  end

  test "category must be in the same household and of the same type" do
    other = households(:parents)
    Categories::Seed.call(other)
    assert_includes build(category: other.categories.find_by!(record_type: "expense", name_zh: "水費")).tap(&:validate).errors.details[:category], { error: :invalid }
    assert_includes build(record_type: "tax").tap(&:validate).errors.details[:category], { error: :wrong_type }
  end

  test "period end year follows the year boundary rule" do
    assert build(period: Period.parse(2025, "12月-1月")).valid?
    record = build(period: Period.parse(2025, "12月-1月"))
    record.period_end_year = 2025
    assert_includes record.tap(&:validate).errors.details[:period_end_year], { error: :year_boundary }
  end

  test "a due date clears the no-due-date reminder repeat" do
    record = build(reminder_frequency: "weekly")
    assert record.valid?
    record.due_on = Date.new(2026, 5, 1)
    record.validate
    assert record.reminder_none?
  end

  test "record numbers count up per household and are never reused" do
    first = build.tap(&:save!)
    second = build.tap(&:save!)
    assert_equal first.record_no + 1, second.record_no
    second.destroy!
    assert_equal first.record_no + 2, build.tap(&:save!).record_no
  end

  test "import context requires the sheet ID and rejects future paid dates" do
    record = build(amount_required: 580, amount_paid: 580, paid_on: Date.current + 2)
    assert record.valid?
    assert_not record.valid?(:import)
    assert_includes record.errors.details[:import_key], { error: :blank }
    assert_includes record.errors.details[:paid_on], { error: :in_future }
  end
end
