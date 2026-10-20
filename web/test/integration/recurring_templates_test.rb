require "test_helper"

class RecurringTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @fee = @home.categories.find_by!(name_zh: "社區管理費")
    sign_in_as users(:alex)
  end

  def params(**overrides)
    { category_id: @fee.id, interval_months: 2, anchor_month: 1, starts_on: "2026-01-01", due_day: 10, due_month_offset: 0,
      lead_days: 7, default_amount: 4064, amount_fixed: "1", currency: "TWD", default_reminder_frequency: "none" }.merge(overrides)
  end

  test "creating a template generates its due bills" do
    travel_to Time.zone.local(2026, 3, 5) do
      post household_recurring_templates_path(@home), params: { recurring_template: params }
      assert_redirected_to household_recurring_templates_path(@home)
      template = @home.recurring_templates.sole
      assert_equal [ "2026 1月-2月", "2026 3月-4月" ], template.records.order(:period_start_month).map { |r| r.period.to_s }
      get household_recurring_templates_path(@home)
      assert_response :success
    end
  end

  test "changing the fixed amount asks first, then updates only untouched unpaid bills" do
    travel_to Time.zone.local(2026, 3, 5) do
      post household_recurring_templates_path(@home), params: { recurring_template: params }
      template = @home.recurring_templates.sole
      jan, mar = template.records.order(:period_start_month).to_a
      jan.update!(amount_paid: 4064, paid_on: Date.new(2026, 1, 10))

      patch household_recurring_template_path(@home, template), params: { recurring_template: params(default_amount: 4200) }
      assert_response :success
      assert_select "strong", text: "NT$4,200"
      assert_equal BigDecimal("4064"), mar.reload.amount_required, "nothing changes before confirming"

      patch household_recurring_template_path(@home, template), params: { recurring_template: params(default_amount: 4200), confirmed: "1" }
      assert_redirected_to household_recurring_templates_path(@home)
      assert_equal [ BigDecimal("4064"), BigDecimal("4200") ], [ jan.reload.amount_required, mar.reload.amount_required ]
      assert RecordEvent.exists?(record_id: mar.id, action: "template_updated")
    end
  end

  test "a new interval updates the started bill in place and regenerates bills not started yet" do
    travel_to Time.zone.local(2026, 4, 28) do
      post household_recurring_templates_path(@home), params: { recurring_template: params(lead_days: 40) }
      template = @home.recurring_templates.sole
      assert_equal 3, template.records.count # 1-2, 3-4, 5-6 (made 4/1)
      current = template.records.find_by!(period_start_month: 3)

      patch household_recurring_template_path(@home, template), params: { recurring_template: params(lead_days: 40, interval_months: 3, period_span_months: 3), confirmed: "1" }
      assert_equal [ 3, 5 ], [ current.reload.period_start_month, current.period_end_month ]
      assert_not template.records.exists?(period_start_month: 5), "5月-6月 hadn't started: deleted"
      assert template.records.exists?(period_start_month: 4), "regenerated under the new schedule (4月-6月)"
    end
  end

  test "deleting a template keeps its bills, unlinked" do
    travel_to Time.zone.local(2026, 3, 5) do
      post household_recurring_templates_path(@home), params: { recurring_template: params }
      template = @home.recurring_templates.sole
      bills = template.records.pluck(:id)
      delete household_recurring_template_path(@home, template)
      assert_equal bills.size, Record.where(id: bills, recurring_template_id: nil).count
    end
  end

  test "an ambiguous period is resolved by picking a bill" do
    2.times { @home.records.create!(record_type: "expense", category: @fee, period: Period.parse(2026, "1月-2月")) }
    travel_to Time.zone.local(2026, 1, 5) do
      post household_recurring_templates_path(@home), params: { recurring_template: params }
      template = @home.recurring_templates.sole
      get household_recurring_templates_path(@home)
      assert_select "p", /2 筆帳單符合/
      pick = Recurring::Generator.matching_bills(template, template.period_at(2026 * 12)).first
      post link_household_recurring_template_path(@home, template, period_index: 2026 * 12, record_id: pick.id)
      assert_equal template, pick.reload.recurring_template
    end
  end

  test "viewers can't manage templates" do
    sign_out
    sign_in_as users(:google_only)
    get household_recurring_templates_path(@home)
    assert_response :success
    post household_recurring_templates_path(@home), params: { recurring_template: params }
    assert_response :forbidden
  end

  test "New Record links to setting up a recurring bill" do
    get new_household_record_path(@home)
    assert_select "a[href=?]", new_household_recurring_template_path(@home)
  end

  test "Save and Make Recurring saves the record, then opens the template filled in from it" do
    water = @home.categories.find_by!(name_zh: "水費")
    get new_household_record_path(@home)
    assert_select "input[type=submit][name=make_recurring]"

    post household_records_path(@home), params: { make_recurring: "Save and Make Recurring", record: { category_id: water.id,
      period_year: 2026, period_start_month: 9, period_end_month: 10, currency: "TWD", amount_required: 600 } }
    record = @home.records.sole
    assert_redirected_to new_household_recurring_template_path(@home, from_record: record.id)
    follow_redirect!
    assert_select "select[name='recurring_template[anchor_month]'] option[selected][value='9']"
  end

  test "Make This Recurring fills the template from the record, which becomes its first bill" do
    water = @home.categories.find_by!(name_zh: "水費")
    record = @home.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "1月-2月"),
      amount_required: 600, due_on: Date.new(2026, 3, 10), currency: "TWD")
    get household_record_path(@home, record)
    assert_select "a[href=?]", new_household_recurring_template_path(@home, from_record: record.id)

    get new_household_recurring_template_path(@home, from_record: record.id)
    assert_select "p", /#{record.title}/
    assert_select "select[name='recurring_template[category_id]'] option[selected][value='#{water.id}']"
    assert_select "select[name='recurring_template[interval_months]'] option[selected][value='2']"
    assert_select "select[name='recurring_template[anchor_month]'] option[selected][value='1']"
    assert_select "input[name='recurring_template[starts_on]'][value='2026-01-01']"
    assert_select "input[name='recurring_template[due_day]'][value='10']"
    assert_select "input[name='recurring_template[due_month_offset]'][value='2']"
    assert_select "input[name='recurring_template[default_amount]'][value='600.0']"

    travel_to Time.zone.local(2026, 3, 5) do
      post household_recurring_templates_path(@home), params: { recurring_template: params(category_id: water.id, anchor_month: 1,
        due_month_offset: 2, default_amount: 600, amount_fixed: "0") }
    end
    template = @home.recurring_templates.sole
    assert_equal [ record ], template.records.to_a, "linked, not duplicated"

    get household_record_path(@home, record)
    assert_select "a[href=?]", edit_household_recurring_template_path(@home, template)
    assert_select "a[href*='from_record']", count: 0
  end
end
