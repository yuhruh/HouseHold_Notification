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

  test "the summary shows only Paid; the Outstanding status filter lists the records still owed" do
    add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    owed = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    get household_records_path(@home)
    assert_select "section[aria-label] th", count: 2
    assert_select "section[aria-label] a[href*='status=outstanding']", 0
    get household_records_path(@home, status: "outstanding")
    assert_select "tbody tr[id=?]", "record_#{owed.id}"
    assert_select "table tbody tr", count: 1 + 2 # the one owed record + the summary's type and total rows
    assert_select "td.text-red-700", /500/
  end

  test "the summary Paid amount links to the records it adds up, keeping the filters (Required is no longer shown)" do
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    partial = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    unpaid = add(amount_required: 700)
    no_amount = add(amount_required: nil)
    get household_records_path(@home)
    required = household_records_path(@home, amount: "required", type: "expense", currency: "TWD")
    paid_link = household_records_path(@home, amount: "paid", type: "expense", currency: "TWD")
    assert_select "a[href=?]", required, 0
    assert_select "a[href=?]", paid_link, "NT$680"

    get required
    assert_equal [ paid, partial, unpaid ].map { |r| "record_#{r.id}" }.sort, css_select("tbody tr[id^=record_]").map { _1["id"] }.sort
    assert_select "span", "有應繳金額的記錄 · TWD"
    assert_select "a[href=?]", household_records_path(@home, type: "expense"), "顯示全部"
    get paid_link
    assert_equal [ paid, partial ].map { |r| "record_#{r.id}" }.sort, css_select("tbody tr[id^=record_]").map { _1["id"] }.sort
    assert_select "tbody tr[id=?]", "record_#{no_amount.id}", 0

    get household_records_path(@home, status: "partial")
    assert_select "a[href=?]", household_records_path(@home, status: "partial", amount: "paid", type: "expense", currency: "TWD"), "NT$100"
  end

  test "list shows records, the summary and a filter by status" do
    add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14), details: "大樓")
    add(amount_required: 600)
    get household_records_path(@home)
    assert_response :success
    assert_select "tbody tr[id^=record_]", 2
    assert_select "section[aria-label] td", text: "NT$580"
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

  test "the list is paged: 20 per page by default, 10 / 20 / 50 or a custom number, remembered on this device" do
    25.times { |i| add(amount_required: 100 + i) }
    get household_records_path(@home)
    assert_select "tbody tr[id^=record_]", 20
    assert_select "p", "第 1–20 筆，共 25 筆"
    assert_select "nav a[href=?]", household_records_path(@home, page: 2), "2"

    get household_records_path(@home, page: 2)
    assert_select "tbody tr[id^=record_]", 5
    assert_select "nav [aria-current=page]", "2"
    get household_records_path(@home, page: 99)
    assert_select "tbody tr[id^=record_]", 5, "past the end shows the last page"

    get household_records_path(@home, per: 10)
    assert_select "tbody tr[id^=record_]", 10
    get household_records_path(@home)
    assert_select "tbody tr[id^=record_]", 10, "the choice is remembered"
    assert_select "select[name=per] option[selected][value='10']"

    get household_records_path(@home, per: "custom", per_custom: 7)
    assert_select "tbody tr[id^=record_]", 7
    assert_select "select[name=per] option[selected][value=custom]"
    assert_select "input[name=per_custom][value='7']"
    get household_records_path(@home, per: "custom", per_custom: 9999)
    assert_select "tbody tr[id^=record_]", 7, "out of range keeps the last choice"
  end

  test "paging keeps the filters, and the summary still counts every matching record" do
    25.times { add(amount_required: 100, amount_paid: 100, paid_on: Date.new(2026, 3, 1)) }
    add(amount_required: 50)
    get household_records_path(@home, status: "paid")
    assert_select "tbody tr[id^=record_]", 20
    assert_select "nav a[href=?]", household_records_path(@home, status: "paid", page: 2)
    assert_select "section[aria-label] td", text: "NT$2,500"
    assert_select "form[data-controller=per-page] input[type=hidden][name=status][value=paid]"
  end

  test "rows still to pay are highlighted: unpaid and partly paid in amber, overdue in red, paid plain" do
    unpaid = add(amount_required: 700)
    partial = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    overdue = add(amount_required: 500, due_on: 3.days.ago.to_date)
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    get household_records_path(@home)
    assert_select "tr#record_#{unpaid.id}.bg-amber-50"
    assert_select "tr#record_#{partial.id}.bg-amber-50"
    assert_select "tr#record_#{overdue.id}.bg-red-50"
    assert_select "tr#record_#{paid.id}.bg-amber-50, tr#record_#{paid.id}.bg-red-50", 0
  end

  test "unpaid rows show the due date (red once overdue) or No due date; paid rows show neither" do
    due = add(amount_required: 700, due_on: Date.current + 10)
    overdue = add(amount_required: 500, due_on: 3.days.ago.to_date)
    undated = add(amount_required: 600)
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14), due_on: Date.current + 10)
    get household_records_path(@home)
    assert_select "tr#record_#{due.id} span.text-gray-500", "到期 #{I18n.l(due.due_on, locale: :"zh-TW")}"
    assert_select "tr#record_#{overdue.id} span.text-red-700", "到期 #{I18n.l(overdue.due_on, locale: :"zh-TW")}"
    assert_select "tr#record_#{undated.id} span.text-gray-500", "未設定到期日"
    assert_select "tr#record_#{paid.id}", text: /到期|未設定到期日/, count: 0
  end

  test "the record page doesn't show the sheet ID" do
    record = add(amount_required: 700, import_key: "125")
    get household_record_path(@home, record)
    assert_response :success
    assert_no_match(/試算表 ID/, response.body)
  end

  test "the form asks how much was paid: Not paid yet, Paid in full or Partly paid, picked from the record" do
    get new_household_record_path(@home)
    assert_select "label", /Amount due|應繳金額/
    assert_select "input[type=radio][name=paid_choice][value=none][checked]"
    full = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    partial = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    get edit_household_record_path(@home, full)
    assert_select "input[type=radio][name=paid_choice][value=full][checked]"
    get edit_household_record_path(@home, partial)
    assert_select "input[type=radio][name=paid_choice][value=partial][checked]"
    assert_select "input[name='record[amount_paid]'][value='100'][step='1']", 1, "TWD amounts are whole numbers"
    assert_select "input[name='record[amount_required]'][value='600'][step='1']"
    usd = add(amount_required: 12.5, currency: "USD")
    get edit_household_record_path(@home, usd)
    assert_select "input[name='record[amount_required]'][value='12.5'][step='0.01']"
  end

  test "the form has Billing Details and Payment Details; the payment window can't end before it starts" do
    get new_household_record_path(@home)
    assert_select "section h2", /Billing Details|帳單資訊/
    assert_select "section h2", /Payment Details|繳費資訊/
    assert_select "input[name='record[payable_from]']"
    assert_select "[data-due-reminder-target=reminder]:not([hidden])"

    post household_records_path(@home), params: { record: form_params(payable_from: "2026-11-01", due_on: "2026-11-30") }
    record = @home.records.order(:id).last
    assert_equal Date.new(2026, 11, 1), record.payable_from
    get household_record_path(@home, record)
    assert_select "dd", I18n.l(Date.new(2026, 11, 1))
    get edit_household_record_path(@home, record)
    assert_select "[data-due-reminder-target=reminder][hidden]", 1, "the no-due-date reminder is hidden while a due date is set"

    assert_no_difference -> { @home.records.count } do
      post household_records_path(@home), params: { record: form_params(payable_from: "2026-12-01", due_on: "2026-11-30") }
    end
    assert_response :unprocessable_content
  end
end
