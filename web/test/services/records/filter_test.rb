require "test_helper"

class Records::FilterTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(record_type: "expense", name_zh: "水費")
    @today = Date.new(2026, 4, 20)
  end

  def add(period, **attrs)
    @home.records.create!({ record_type: "expense", category: @water, period: Period.parse(*period) }.merge(attrs))
  end

  def filter(**params) = Records::Filter.new(@home, params, today: @today)

  test "statuses partition the records, with overdue bound to today" do
    paid = add([ 2026, "1月-2月" ], amount_required: 580, amount_paid: 580, paid_on: @today)
    partial = add([ 2026, "1月-2月" ], amount_required: 580, amount_paid: 300, paid_on: @today)
    overdue = add([ 2026, "3月-4月" ], amount_required: 600, due_on: @today - 1)
    unpaid = add([ 2026, "3月-4月" ], amount_required: 600, due_on: @today)
    no_amount = add([ 2026, "5月-6月" ])

    assert_equal [ paid ], filter(status: "paid").records.to_a
    assert_equal [ partial ], filter(status: "partial").records.to_a
    assert_equal [ overdue ], filter(status: "overdue").records.to_a
    assert_equal [ no_amount, unpaid ].sort_by(&:id), filter(status: "unpaid").records.sort_by(&:id)
    [ paid, partial, overdue, unpaid, no_amount ].each { |r| assert_equal filter(status: r.status(today: @today).to_s).records.include?(r), true }
  end

  test "not fully paid records come first, each group newest period first" do
    old_paid = add([ 2025, "11月-12月" ], amount_required: 500, amount_paid: 500, paid_on: @today)
    new_paid = add([ 2026, "3月-4月" ], amount_required: 600, amount_paid: 600, paid_on: @today)
    old_unpaid = add([ 2025, "9月-10月" ], amount_required: 400)
    partial = add([ 2026, "1月-2月" ], amount_required: 580, amount_paid: 300, paid_on: @today)
    new_unpaid = add([ 2026, "5月-6月" ])
    assert_equal [ new_unpaid, partial, old_unpaid, new_paid, old_paid ], filter.records.to_a
  end

  test "year and month select by billing-period overlap, including periods crossing the year" do
    crossing = add([ 2025, "12月-1月" ])
    spring = add([ 2026, "3月-4月" ])
    assert_equal [ crossing ], filter(year: 2026, month: 1).records.to_a
    assert_equal [ spring, crossing ], filter(year: 2026).records.to_a
    assert_equal [ crossing ], filter(year: 2025).records.to_a
    assert_includes filter.years, 2025
  end

  test "summary sums full amounts per type and currency; outstanding counts only unsettled rows" do
    add([ 2026, "1月-2月" ], amount_required: 580, amount_paid: 580, paid_on: @today)
    add([ 2026, "3月-4月" ], amount_required: 600, amount_paid: 100, paid_on: @today)
    add([ 2026, "3月-4月" ], currency: "USD", amount_required: 12.5)

    twd = filter.totals.find { |t| t.currency == "TWD" }
    assert_equal [ 1180, 680, 500 ], [ twd.required, twd.paid, twd.outstanding ].map(&:to_i)
    usd = filter.totals.find { |t| t.currency == "USD" }
    assert_equal BigDecimal("12.5"), usd.outstanding
  end

  test "search matches title, details and payment note" do
    hit = add([ 2026, "1月-2月" ], details: "大樓 A 棟")
    add([ 2026, "1月-2月" ], payment_note: "cash")
    assert_equal [ hit ], filter(q: "A 棟").records.to_a
  end
end
