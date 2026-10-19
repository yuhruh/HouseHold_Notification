require "test_helper"

class RecordsTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(record_type: "expense", name_zh: "水費")
    @ac = @home.categories.find_by!(record_type: "maintenance", name_zh: "冷氣清洗")
    sign_in_as users(:alex)
  end

  def add(**attrs)
    @home.records.create!({ record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月") }.merge(attrs))
  end

  def form_params(**overrides)
    { category_id: @water.id, title: "", period_year: 2025, period_start_month: 12, period_end_month: 1, currency: "TWD",
      amount_required: "580", amount_paid: "", reminder_frequency: "none" }.merge(overrides)
  end

  test "list shows records, the summary and a filter by status" do
    add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14), details: "大樓")
    add(amount_required: 600)
    get household_records_path(@home)
    assert_response :success
    assert_select "tbody tr[id^=record_]", 2
    assert_select "td", text: "NT$1,180"
    get household_records_path(@home, status: "paid")
    assert_select "tbody tr[id^=record_]", 1
  end

  test "create takes the type from the category, defaults the title and logs the event" do
    post household_records_path(@home), params: { record: form_params }
    record = @home.records.sole
    assert_redirected_to household_record_path(@home, record)
    assert_equal [ "expense", "水費", 2026 ], [ record.record_type, record.title, record.period_end_year ]
    assert_equal users(:alex), record.created_by
    assert_equal [ "created" ], RecordEvent.where(record_id: record.id).pluck(:action)
    get household_record_path(@home, record)
    assert_response :success
  end

  test "invalid input re-renders the form with errors" do
    post household_records_path(@home), params: { record: form_params(amount_paid: "700") }
    assert_response :unprocessable_content
    assert_select "ul.bg-red-50 li"
    assert_empty @home.records
  end

  test "a stale edit is refused" do
    record = add(amount_required: 580)
    stale = record.lock_version
    record.update!(details: "changed elsewhere")
    patch household_record_path(@home, record), params: { record: form_params(lock_version: stale, details: "mine") }
    assert_response :conflict
    assert_equal "changed elsewhere", record.reload.details
  end

  test "mark paid fills Paid from Required and sets today's date" do
    record = add(amount_required: 580, amount_paid: 300, paid_on: Date.new(2026, 3, 1))
    post mark_paid_household_record_path(@home, record)
    record.reload
    assert record.settled
    assert_equal [ 580, Time.current.in_time_zone("Asia/Taipei").to_date ], [ record.amount_paid.to_i, record.paid_on ]
    assert_equal [ "marked_paid" ], RecordEvent.where(record_id: record.id).pluck(:action)
  end

  test "mark paid with a blank Required asks for the amount and sets both" do
    record = add
    get mark_paid_household_record_path(@home, record)
    assert_select "input[name=amount]"
    post mark_paid_household_record_path(@home, record)
    assert_response :unprocessable_content
    post mark_paid_household_record_path(@home, record), params: { amount: "612" }
    record.reload
    assert record.settled
    assert_equal [ 612, 612 ], [ record.amount_required.to_i, record.amount_paid.to_i ]
  end

  test "maintenance with no amounts is marked done with just the date" do
    record = add(record_type: "maintenance", category: @ac)
    post mark_paid_household_record_path(@home, record)
    assert record.reload.settled
    assert_nil record.amount_paid
  end

  test "delete keeps a snapshot in the activity log" do
    record = add(amount_required: 580, details: "大樓")
    delete household_record_path(@home, record)
    assert_redirected_to household_records_path(@home)
    assert_not Record.exists?(record.id)
    event = RecordEvent.find_by!(record_id: record.id, action: "deleted")
    assert_equal "大樓", event.diff["details"]
  end

  test "a viewer sees records but can't change them" do
    record = add(amount_required: 580)
    sign_out
    sign_in_as users(:google_only)
    get household_records_path(@home)
    assert_response :success
    assert_select "a", text: I18n.t("records.index.new", locale: "zh-TW"), count: 0
    post household_records_path(@home), params: { record: form_params }
    assert_response :forbidden
    post mark_paid_household_record_path(@home, record)
    assert_response :forbidden
    delete household_record_path(@home, record)
    assert_response :forbidden
  end

  test "another household's record is not found" do
    parents = households(:parents)
    Categories::Seed.call(parents)
    other = parents.records.create!(record_type: "expense", category: parents.categories.find_by!(name_zh: "水費"), period: Period.parse(2026, "1月"))
    get household_record_path(@home, other)
    assert_response :not_found
    post household_records_path(@home), params: { record: form_params(category_id: parents.categories.first.id) }
    assert_response :unprocessable_content
  end

  test "payment methods: add, edit, archive; archived ones leave the record form" do
    post household_payment_methods_path(@home), params: { payment_method: { name: "玉山 ubear", kind: "card", last4: "1234" } }
    card = @home.payment_methods.sole
    assert_redirected_to household_payment_methods_path(@home)
    patch household_payment_method_path(@home, card), params: { payment_method: { name: "玉山 ubear 卡" } }
    assert_equal "玉山 ubear 卡", card.reload.name
    post archive_household_payment_method_path(@home, card)
    assert card.reload.archived_at
    get new_household_record_path(@home)
    assert_select "option", text: /玉山/, count: 0
    get household_payment_methods_path(@home)
    assert_response :success

    sign_out
    sign_in_as users(:google_only)
    post household_payment_methods_path(@home), params: { payment_method: { name: "x", kind: "cash" } }
    assert_response :forbidden
  end
end
