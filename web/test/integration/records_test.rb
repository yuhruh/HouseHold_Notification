require "test_helper"

class RecordsTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(record_type: "expense", name_zh: "水費")
    @ac = @home.categories.find_by!(record_type: "maintenance", name_zh: "冷氣清洗")
    sign_in_as users(:alex)
  end

  # The app's "today" is the signed-in user's local date (Asia/Taipei), not the server's UTC one
  def today = Time.find_zone!(users(:alex).time_zone).today

  def add(**attrs)
    @home.records.create!({ record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月") }.merge(attrs))
  end

  def form_params(**overrides)
    { category_id: @water.id, title: "", period_year: 2025, period_start_month: 12, period_end_month: 1, currency: "TWD",
      amount_required: "580", amount_paid: "", reminder_frequency: "none" }.merge(overrides)
  end

  test "Past Records lists earlier periods of the same category and details, newest first, in a closing menu" do
    older = add(period: Period.parse(2025, "11月-12月"), details: "A", amount_required: 500, amount_paid: 500, paid_on: Date.new(2026, 1, 10))
    old = add(period: Period.parse(2026, "1月-2月"), details: "A", amount_required: 520)
    current = add(period: Period.parse(2026, "3月-4月"), details: "A")
    add(period: Period.parse(2025, "9月-10月"), details: "B")
    add(period: Period.parse(2026, "5月-6月"), details: "A")
    get household_record_path(@home, current)
    assert_select "details#past_records[data-controller=dropdown] summary", /過去的記錄（2）/
    assert_select "details#past_records li" do |items|
      assert_equal [ "past_record_#{old.id}", "past_record_#{older.id}" ], items.map { it["id"] }
    end
    assert_select "li#past_record_#{older.id} a[href=?]", household_record_path(@home, older), text: /2026-01-10 已繳/
    assert_select "details#past_records a[href=?]", household_records_path(@home, category_id: @water.id, q: "A", from: current.id)
    get household_record_path(@home, older)
    assert_select "details#past_records", 0, "the earliest record has no past records"
  end

  test "the summary shows only Paid; the Outstanding status filter lists the records still owed" do
    add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    owed = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    get household_records_path(@home)
    assert_select "section[aria-label] th", count: 2
    assert_select "section[aria-label] a[href*='status=outstanding']", 0
    get household_records_path(@home, status: "outstanding")
    assert_select "li[id=?]", "record_#{owed.id}"
    assert_select "li[id^=record_]", 1
    assert_select "li span[data-outstanding]", /500/
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
    assert_equal [ paid, partial, unpaid ].map { |r| "record_#{r.id}" }.sort, css_select("li[id^=record_]").map { _1["id"] }.sort
    assert_select "span", "有應繳金額的記錄 · TWD"
    assert_select "a[href=?]", household_records_path(@home, type: "expense"), "顯示全部"
    get paid_link
    assert_equal [ paid, partial ].map { |r| "record_#{r.id}" }.sort, css_select("li[id^=record_]").map { _1["id"] }.sort
    assert_select "li[id=?]", "record_#{no_amount.id}", 0

    get household_records_path(@home, status: "partial")
    assert_select "a[href=?]", household_records_path(@home, status: "partial", amount: "paid", type: "expense", currency: "TWD"), "NT$100"
  end

  test "list shows records, the summary and a filter by status" do
    add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14), details: "大樓")
    add(amount_required: 600)
    get household_records_path(@home)
    assert_response :success
    assert_select "li[id^=record_]", 2
    assert_select "section[aria-label] td", text: "NT$580"
    get household_records_path(@home, status: "paid")
    assert_select "li[id^=record_]", 1
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

  def taipei_today = Time.current.in_time_zone("Asia/Taipei").to_date

  test "Record Payment opens only the payment, filled in (paid in full, today, last payment method), with the bill as a summary" do
    card = @home.payment_methods.create!(name: "Card", kind: "card")
    add(amount_required: 100, amount_paid: 100, paid_on: Date.new(2026, 3, 1), payment_method: card)
    record = add(amount_required: 580, due_on: taipei_today + 5)
    get household_record_path(@home, record)
    assert_select "a[href=?]", edit_household_record_path(@home, record, pay: 1)
    get edit_household_record_path(@home, record, pay: 1)
    assert_select "h1", /記錄繳費/
    assert_select "#billing_heading", 0
    assert_select "select[name='record[category_id]'], input[name='record[due_on]']", 0, "the bill's own fields are on Edit Details"
    assert_select "a[href=?]", edit_household_record_path(@home, record), text: "金額不對？編輯帳單資訊"
    assert_select "input#paid_choice_full[checked]"
    assert_select "input#paid_choice_partial"
    assert_select "input#paid_choice_none", 0
    assert_select "input[name='record[amount_paid]'][value=?]", "580"
    assert_select "input[name='record[paid_on]'][value=?]", taipei_today.iso8601
    assert_select "select[name='record[payment_method_id]'] option[selected][value=?]", card.id.to_s
    assert_select "input[name=pay]"
    assert_nil record.reload.paid_on, "nothing is saved until Save"
  end

  test "saving the payment logs Marked Paid and says the payment was saved" do
    record = add(amount_required: 580)
    patch household_record_path(@home, record), params: { pay: 1, record: form_params(amount_paid: "580", paid_on: taipei_today.iso8601, lock_version: record.lock_version) }
    assert record.reload.settled
    assert_equal [ "marked_paid" ], RecordEvent.where(record_id: record.id).pluck(:action)
    assert_equal "已儲存「水費」的繳費。", flash[:notice]
  end

  test "an empty Payment Note or Details isn't logged as a change" do
    record = add(amount_required: 580)
    patch household_record_path(@home, record), params: { pay: 1, record: form_params(amount_paid: "580", paid_on: taipei_today.iso8601, details: "", payment_note: "", lock_version: record.lock_version) }
    assert_nil record.reload.payment_note
    diff = RecordEvent.where(record_id: record.id).sole.diff
    assert_includes diff.keys, "paid_on"
    assert_empty diff.keys & %w[details payment_note]
  end

  test "the bill page: one big Record Payment, Edit Details on the bill's card, Edit Payment once something is paid" do
    record = add(amount_required: 580)
    get household_record_path(@home, record)
    assert_select "a.w-full[href=?]", edit_household_record_path(@home, record, pay: 1), text: /記錄繳費/
    assert_select "section[aria-labelledby=bill_details_heading] a[href=?]", edit_household_record_path(@home, record), text: /編輯帳單資訊/
    assert_select "section[aria-labelledby=payment_details_heading]", text: /尚未繳費。繳了之後按上面的「記錄繳費」/
    assert_select "a[href*='payment=1']", 0
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 3, 1))
    get household_record_path(@home, paid)
    assert_select "a[href*='pay=1']", 0
    assert_select "section[aria-labelledby=payment_details_heading] a[href=?]", edit_household_record_path(@home, paid, payment: 1), text: /編輯繳費/
  end

  test "Edit Details has only the bill; a paid record's Edit Payment isn't filled in and can undo the payment" do
    record = add(amount_required: 580)
    get edit_household_record_path(@home, record)
    assert_select "h1", /編輯帳單資訊/
    assert_select "#billing_heading"
    assert_select "input[name=paid_choice], input[name='record[amount_paid]'], input[name='record[paid_on]']", 0
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 3, 1), payment_note: "ATM")
    [ { payment: 1 }, { pay: 1 } ].each do |param|
      get edit_household_record_path(@home, paid, **param)
      assert_select "h1", /編輯繳費/
      assert_select "input#paid_choice_full[checked]"
      assert_select "input#paid_choice_none"
      assert_select "input[name='record[paid_on]'][value=?]", "2026-03-01" # left as saved
      assert_select "input[name=payment]"
    end
    patch household_record_path(@home, paid), params: { payment: 1, record: { amount_paid: "", paid_on: "", payment_note: "ATM", lock_version: paid.lock_version } }
    assert_not paid.reload.settled
    assert_nil paid.paid_on
    assert_equal "updated", RecordEvent.where(record_id: paid.id).sole.action
  end

  test "Edit Details on a bill paid in full: a corrected amount due keeps it paid in full" do
    record = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 3, 1))
    patch household_record_path(@home, record), params: { record: form_params(amount_required: "600", lock_version: record.lock_version).except(:amount_paid) }
    record.reload
    assert_equal [ 600, 600 ], [ record.amount_required.to_i, record.amount_paid.to_i ]
    assert record.settled
    partial = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 3, 1))
    patch household_record_path(@home, partial), params: { record: form_params(amount_required: "650", lock_version: partial.lock_version).except(:amount_paid) }
    assert_equal 100, partial.reload.amount_paid.to_i, "a part payment stays as it was"
  end

  test "Record Payment on a bill with no amount due asks for the amount there" do
    record = add
    get edit_household_record_path(@home, record, pay: 1)
    assert_select "input[name='record[amount_required]']"
    assert_select "p", text: "還沒填應繳金額"
  end

  def filter(**attrs) = add(record_type: "maintenance", category: @ac, title: "濾網/濾芯更換", amount_required: 925, **attrs)

  test "maintenance reads as a task: Not done yet with its expected cost, and Mark Done" do
    record = filter
    get household_record_path(@home, record)
    assert_select "[role=status] p.text-amber-900", "尚未完成"
    assert_select "[role=status] p.text-gray-700", "未設定到期日 · 預計花費 NT$925"
    assert_select "dt", "預計花費"
    assert_select "a[href=?]", edit_household_record_path(@home, record, pay: 1), text: /標記完成/
    get household_records_path(@home)
    assert_select "li#record_#{record.id}", text: /待完成.*預計花費 NT\$925/m
  end

  test "Mark Done fills in today and the expected cost; the cost saved becomes the task's cost" do
    record = filter
    get edit_household_record_path(@home, record, pay: 1)
    assert_select "h1", /標記完成/
    assert_select "input[name='record[amount_paid]'][value=?]", "925"
    assert_select "input[name='record[paid_on]'][value=?]", taipei_today.iso8601
    assert_select "input[name='record[next_due_on]']"
    assert_select "input[name=paid_choice]", 0
    patch household_record_path(@home, record), params: { pay: 1, record: form_params(category_id: @ac.id, title: "濾網/濾芯更換", amount_required: "925", amount_paid: "880", paid_on: taipei_today.iso8601, lock_version: record.lock_version) }
    record.reload
    assert record.settled
    assert_equal [ 880, 880 ], [ record.amount_required.to_i, record.amount_paid.to_i ]
    assert_equal "已將「濾網/濾芯更換」標記為完成。", flash[:notice]
    get household_record_path(@home, record)
    assert_select "[role=status] p.text-green-800", "#{I18n.l(taipei_today, locale: :"zh-TW")} 完成"
    assert_select "[role=status] p.text-gray-700", "花費 NT$880"
    get household_records_path(@home)
    assert_select "li#record_#{record.id}", text: /已完成.*花費 NT\$880/m
  end

  test "Mark Done with the cost emptied is done with no cost" do
    record = filter
    patch household_record_path(@home, record), params: { pay: 1, record: form_params(category_id: @ac.id, amount_required: "925", amount_paid: "", paid_on: taipei_today.iso8601, lock_version: record.lock_version) }
    record.reload
    assert record.settled
    assert_nil record.amount_paid
    assert_nil record.amount_required
  end

  test "maintenance with no amounts is paid with just the date" do
    record = add(record_type: "maintenance", category: @ac)
    patch household_record_path(@home, record), params: { pay: 1, record: form_params(category_id: @ac.id, amount_required: "", amount_paid: "", paid_on: taipei_today.iso8601, lock_version: record.lock_version) }
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

  test "each record is a card that opens it, with no Mark Paid button in the list" do
    record = add(amount_required: 580)
    get household_records_path(@home)
    assert_select "li#record_#{record.id} a[href=?]", household_record_path(@home, record)
    assert_select "form[action*=mark_paid], a[href*=mark_paid]", 0
  end

  test "the record page shows a status line worked out from the record, with no ✅ / ❌" do
    unpaid = add(amount_required: 580, due_on: today + 10)
    get household_record_path(@home, unpaid)
    assert_select "h1", text: /[✅❌]/, count: 0
    assert_select "[role=status] p.text-amber-900", "尚未繳費 · 10 天後到期"
    assert_select "[role=status] p.text-gray-700", "#{I18n.l(unpaid.due_on, locale: :"zh-TW")} 到期 · 還要繳 NT$580"

    overdue = add(amount_required: 580, amount_paid: 80, paid_on: today - 5, due_on: today - 3)
    get household_record_path(@home, overdue)
    assert_select "[role=status] p.text-red-700", "已逾期 3 天 · 還要繳 NT$500"

    partial = add(amount_required: 600, amount_paid: 100, paid_on: today - 2)
    get household_record_path(@home, partial)
    assert_select "[role=status] p.text-amber-900", "部分已繳 · 還要繳 NT$500"
    assert_select "[role=status] p.text-gray-700", "未設定到期日"

    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    get household_record_path(@home, paid)
    assert_select "[role=status] p.text-green-800", "#{I18n.l(paid.paid_on, locale: :"zh-TW")} 已繳"
    assert_select "[role=status] p.text-gray-700", "NT$580"
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
    get edit_household_record_path(@home, record, pay: 1)
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

  def pay_with_new_method(record, **method)
    patch household_record_path(@home, record), params: { pay: 1, record: { amount_paid: "580", paid_on: taipei_today.iso8601, payment_method_id: "new", lock_version: record.lock_version },
                                                          new_payment_method: { name: "國泰 CUBE", kind: "card", last4: "5678" }.merge(method) }
  end

  test "Record Payment offers + New payment method; the one typed in is saved with the payment and listed in Settings" do
    record = add(amount_required: 580)
    get edit_household_record_path(@home, record, pay: 1)
    assert_select "select[name='record[payment_method_id]'] option[value=new]", "＋ 新增付款方式…"
    assert_select "[data-new-payment-method-target=fields][hidden] input[name='new_payment_method[name]']"
    pay_with_new_method(record)
    method = @home.payment_methods.sole
    assert_equal [ "國泰 CUBE", "card", "5678" ], [ method.name, method.kind, method.last4 ]
    assert_equal method, record.reload.payment_method
    assert record.settled
    assert_equal "已儲存「水費」的繳費。已將「國泰 CUBE ··5678」加到付款方式。", flash[:notice]
    get household_payment_methods_path(@home)
    assert_select "li", text: /國泰 CUBE ··5678/
  end

  test "+ New payment method with a name the household has picks that one; Cash keeps no last digits" do
    card = @home.payment_methods.create!(name: "玉山 ubear", kind: "card", last4: "1234")
    record = add(amount_required: 580)
    pay_with_new_method(record, name: "  玉山   UBEAR ", last4: "9999")
    assert_equal [ card ], @home.payment_methods.to_a
    assert_equal card, record.reload.payment_method
    other = add(amount_required: 580)
    pay_with_new_method(other, name: "LINE Pay", kind: "e_wallet", last4: "1111")
    assert_nil @home.payment_methods.find_by!(name: "LINE Pay").last4
  end

  test "+ New payment method: a card number as the name or a bad Last 4 saves nothing, and the form comes back as typed" do
    record = add(amount_required: 580)
    pay_with_new_method(record, name: "4123 4567-8901 5678")
    assert_response :unprocessable_content
    assert_select "ul.bg-red-50 li", /看起來像卡號/
    assert_select "option[value=new][selected]"
    assert_select "[data-new-payment-method-target=fields]:not([hidden]) input[name='new_payment_method[name]'][value=?]", "4123 4567-8901 5678"
    pay_with_new_method(record, last4: "56a8")
    assert_response :unprocessable_content
    assert_empty @home.payment_methods
    assert_nil record.reload.paid_on
  end

  test "+ New payment method isn't added when the payment can't be saved" do
    record = add(amount_required: 580)
    patch household_record_path(@home, record), params: { pay: 1, record: { amount_paid: "900", paid_on: taipei_today.iso8601, payment_method_id: "new", lock_version: record.lock_version },
                                                          new_payment_method: { name: "國泰 CUBE", kind: "card" } }
    assert_response :unprocessable_content
    assert_empty @home.payment_methods
    assert_select "option[value=new][selected]"
  end

  test "the list is paged: 20 per page by default, 10 / 20 / 50 or a custom number, remembered on this device" do
    25.times { |i| add(amount_required: 100 + i) }
    get household_records_path(@home)
    assert_select "li[id^=record_]", 20
    assert_select "p", "第 1–20 筆，共 25 筆"
    assert_select "nav a[href=?]", household_records_path(@home, page: 2), "2"

    get household_records_path(@home, page: 2)
    assert_select "li[id^=record_]", 5
    assert_select "nav [aria-current=page]", "2"
    get household_records_path(@home, page: 99)
    assert_select "li[id^=record_]", 5, "past the end shows the last page"

    get household_records_path(@home, per: 10)
    assert_select "li[id^=record_]", 10
    get household_records_path(@home)
    assert_select "li[id^=record_]", 10, "the choice is remembered"
    assert_select "select[name=per] option[selected][value='10']"

    get household_records_path(@home, per: "custom", per_custom: 7)
    assert_select "li[id^=record_]", 7
    assert_select "select[name=per] option[selected][value=custom]"
    assert_select "input[name=per_custom][value='7']"
    get household_records_path(@home, per: "custom", per_custom: 9999)
    assert_select "li[id^=record_]", 7, "out of range keeps the last choice"
  end

  test "paging keeps the filters, and the summary still counts every matching record" do
    25.times { add(amount_required: 100, amount_paid: 100, paid_on: Date.new(2026, 3, 1)) }
    add(amount_required: 50)
    get household_records_path(@home, status: "paid")
    assert_select "li[id^=record_]", 20
    assert_select "nav a[href=?]", household_records_path(@home, status: "paid", page: 2)
    assert_select "section[aria-label] td", text: "NT$2,500"
    assert_select "form[data-controller=per-page] input[type=hidden][name=status][value=paid]"
  end

  test "cards still to pay are highlighted: unpaid and partly paid in amber, overdue in red, paid plain" do
    unpaid = add(amount_required: 700)
    partial = add(amount_required: 600, amount_paid: 100, paid_on: Date.new(2026, 4, 14))
    overdue = add(amount_required: 500, due_on: 3.days.ago.to_date)
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14))
    get household_records_path(@home)
    assert_select "li#record_#{unpaid.id} a.bg-amber-50"
    assert_select "li#record_#{partial.id} a.bg-amber-50"
    assert_select "li#record_#{overdue.id} a.bg-red-50"
    assert_select "li#record_#{paid.id} a.bg-amber-50, li#record_#{paid.id} a.bg-red-50", 0
  end

  test "unpaid cards show the due date (red once overdue) or No due date; paid cards show neither" do
    due = add(amount_required: 700, due_on: Date.current + 10)
    overdue = add(amount_required: 500, due_on: 3.days.ago.to_date)
    undated = add(amount_required: 600)
    paid = add(amount_required: 580, amount_paid: 580, paid_on: Date.new(2026, 4, 14), due_on: Date.current + 10)
    get household_records_path(@home)
    assert_select "li#record_#{due.id} span.text-gray-600", "到期 #{I18n.l(due.due_on, locale: :"zh-TW")}"
    assert_select "li#record_#{overdue.id} span.text-red-700", "到期 #{I18n.l(overdue.due_on, locale: :"zh-TW")}"
    assert_select "li#record_#{undated.id} span.text-gray-600", "未設定到期日"
    assert_select "li#record_#{paid.id}", text: /到期|未設定到期日/, count: 0
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
    get edit_household_record_path(@home, full, payment: 1)
    assert_select "input[type=radio][name=paid_choice][value=full][checked]"
    get edit_household_record_path(@home, partial, payment: 1)
    assert_select "input[type=radio][name=paid_choice][value=partial][checked]"
    assert_select "input[name='record[amount_paid]'][value='100'][step='1']", 1, "TWD amounts are whole numbers"
    get edit_household_record_path(@home, partial)
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
