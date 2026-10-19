require "test_helper"

class RemindersTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    sign_in_as users(:alex)
  end

  # The app's "today" is the signed-in user's local date (Asia/Taipei), not the server's UTC one;
  # between 00:00 and 08:00 Taipei they differ
  def today = Time.find_zone!(users(:alex).time_zone).today

  def bill(**attrs)
    @home.records.create!({ record_type: "expense", category: @water, period: Period.parse(2026, "9月-10月"), amount_required: 580 }.merge(attrs))
  end

  test "upcoming groups overdue, due soon, maintenance and no-due-date bills" do
    bill(due_on: today - 2)
    bill(due_on: today + 5, details: "B")
    bill(details: "C")
    get household_upcoming_path(@home)
    assert_response :success
    assert_select "h2", /逾期 \(1\)/
    assert_select "h2", /30 天內到期 \(1\)/
    assert_select "h2", /未設定到期日 \(1\)/
  end

  test "snooze is personal and can be cancelled; past or far dates are refused" do
    record = bill(due_on: today)
    post snooze_household_record_path(@home, record, days: 7)
    assert_equal today + 7, ReminderSnooze.find_by!(record:, user: users(:alex)).until_on
    post snooze_household_record_path(@home, record, until_on: (today + 90).iso8601)
    assert_equal today + 7, ReminderSnooze.find_by!(record:).until_on
    delete snooze_household_record_path(@home, record)
    assert_empty ReminderSnooze.where(record:)

    sign_out
    sign_in_as users(:google_only)
    post snooze_household_record_path(@home, record, days: 3)
    assert ReminderSnooze.exists?(record:, user: users(:google_only)), "viewers can snooze"
  end

  test "restart reminders after the cap is logged" do
    record = bill(due_on: today - 40)
    get household_record_path(@home, record)
    assert_select "span", "提醒已停止"
    post restart_reminders_household_record_path(@home, record)
    assert_equal today, record.reload.reminders_restarted_on
    assert RecordEvent.exists?(record_id: record.id, action: "reminders_restarted")
  end

  test "maintenance Done opens a prefilled record in the same chain and clears the old next-due date" do
    ac = @home.categories.find_by!(name_zh: "冷氣清洗")
    old = @home.records.create!(record_type: "maintenance", category: ac, details: "客廳", period: Period.parse(2026, "4月"),
      paid_on: Date.new(2026, 4, 1), next_due_on: today)
    get done_household_record_path(@home, old)
    assert_select "input[name='record[details]'][value='客廳']"
    assert_select "input[name=continues_id][value='#{old.id}']"
    post household_records_path(@home), params: { continues_id: old.id, record: { category_id: ac.id, details: "客廳",
      period_year: today.year, period_start_month: today.month, period_end_month: today.month,
      paid_on: today.iso8601, next_due_on: (today + 180).iso8601, currency: "TWD", reminder_frequency: "none" } }
    assert_nil old.reload.next_due_on
    assert_equal today + 180, @home.records.order(:id).last.next_due_on
  end

  test "inbox lists notifications and marks them read; preferences save per household" do
    Notification.create!(household: @home, user: users(:alex), kind: "reminder_digest", title: "我的家：1 筆帳單需要處理", body: "水費")
    get household_records_path(@home)
    assert_select "header a[href='#{notifications_path}'] span", "1"
    get notifications_path
    assert_select "li", /水費/
    assert_select "header a[href='#{household_upcoming_path(@home)}']", 1, "the header keeps household links outside a household"
    assert_empty users(:alex).notifications.unread

    patch account_notification_preference_path(@home.id), params: { notification_preference: { email: "0", web_push: "1" } }
    assert_redirected_to account_path(anchor: "notifications")
    assert_not NotificationPreference.find_by!(user: users(:alex), household: @home).email
    get account_path
    assert_response :success
  end
end
