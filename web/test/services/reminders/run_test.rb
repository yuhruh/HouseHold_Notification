require "test_helper"

class Reminders::RunTest < ActiveJob::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @alex = users(:alex) # owner, Asia/Taipei, reminder hour 8
  end

  def bill(**attrs)
    @home.records.create!({ record_type: "expense", category: @water, period: Period.parse(2026, "9月-10月"), amount_required: 580,
      due_on: Date.new(2026, 10, 20) }.merge(attrs))
  end

  def run_at(time) = travel_to(time) { Reminders::Run.call }
  def taipei(*args) = Time.find_zone!("Asia/Taipei").local(*args)
  def deliveries(user = @alex) = ReminderDelivery.where(user:).order(:id)

  test "nothing before the member's reminder hour; at 08:00 one digest per channel; later runs add nothing" do
    bill
    run_at(taipei(2026, 10, 20, 7, 30))
    assert_empty deliveries
    assert_enqueued_jobs 2, only: DeliverReminderJob do
      run_at(taipei(2026, 10, 20, 8, 5))
    end
    assert_equal %w[in_app email web_push], deliveries.pluck(:channel)
    assert_equal %w[sent pending pending], deliveries.pluck(:status)
    note = @alex.notifications.sole
    assert_match "我的家：1 筆帳單需要處理", note.title
    assert_match "今天到期", note.body
    run_at(taipei(2026, 10, 20, 9, 5))
    assert_equal 3, deliveries.count
  end

  test "a bill due today that hasn't reminded this member yet gets one same-day addition" do
    bill(due_on: Date.new(2026, 10, 23))
    run_at(taipei(2026, 10, 20, 8, 5)) # due soon digest
    late = bill(due_on: Date.new(2026, 10, 20), details: "B 棟")
    run_at(taipei(2026, 10, 20, 14, 5))
    assert_equal [ false, false, false, true, true, true ], deliveries.pluck(:addition)
    assert_equal [ late.id ], deliveries.last.reminder_logs.pluck(:record_id)
    bill(due_on: Date.new(2026, 10, 19), details: "C 棟")
    run_at(taipei(2026, 10, 20, 16, 5))
    assert_equal 6, deliveries.count, "at most one addition per day"
  end

  test "maintenance bills are worded as maintenance" do
    ac = @home.categories.find_by!(name_zh: "濾網/濾芯更換")
    @home.records.create!(record_type: "maintenance", category: ac, details: "主臥", period: Period.parse(2026, "10月"), due_on: Date.new(2026, 10, 20))
    run_at(taipei(2026, 10, 20, 8, 5))
    assert_match "今天該保養", @alex.notifications.sole.body
  end

  test "a late send words itself from today" do
    bill
    run_at(taipei(2026, 10, 21, 8, 5)) # due_today stage, delivered a day late
    assert_match "已逾期 1 天", @alex.notifications.sole.body
  end

  test "viewers default to in-app only; owners also get email" do
    bill
    run_at(taipei(2026, 10, 20, 8, 5))
    assert_equal [ "in_app" ], deliveries(users(:google_only)).pluck(:channel)
    NotificationPreference.for(memberships(:sam_home)).update!(email: true, web_push: false)
    bill(details: "B 棟", due_on: Date.new(2026, 10, 23))
    run_at(taipei(2026, 10, 23, 8, 5))
    assert_includes deliveries(users(:google_only)).pluck(:channel), "email"
  end

  test "a snooze silences that member only, then sends one 'snooze ended' reminder" do
    record = bill
    ReminderSnooze.create!(record:, user: @alex, until_on: Date.new(2026, 10, 24))
    run_at(taipei(2026, 10, 20, 8, 5))
    assert_empty deliveries
    assert ReminderLog.where(record:, user: @alex, snoozed: true).exists?
    assert_equal 1, deliveries(users(:google_only)).count, "other members keep their reminders"
    run_at(taipei(2026, 10, 24, 8, 5))
    assert_match "已逾期 4 天", @alex.notifications.last.body, "the D+3 stage was snoozed; on the 24th nothing new is scheduled"
  end

  test "paid records stop reminding and paying clears snoozes" do
    record = bill
    ReminderSnooze.create!(record:, user: @alex, until_on: Date.new(2026, 10, 24))
    record.update!(amount_paid: 580, paid_on: Date.new(2026, 10, 19))
    assert_empty record.reminder_snoozes
    run_at(taipei(2026, 10, 20, 8, 5))
    assert_empty deliveries
  end

  test "a next-due reminder is silent while a bill of the same chain is due within 30 days" do
    ac = @home.categories.find_by!(name_zh: "冷氣清洗")
    @home.records.create!(record_type: "maintenance", category: ac, details: "客廳", period: Period.parse(2026, "4月"),
      paid_on: Date.new(2026, 4, 1), next_due_on: Date.new(2026, 10, 20))
    @home.records.create!(record_type: "maintenance", category: ac, details: "客廳", period: Period.parse(2026, "10月"),
      amount_required: 1500, due_on: Date.new(2026, 11, 5))
    run_at(taipei(2026, 10, 20, 8, 5))
    assert_no_match(/保養/, @alex.notifications.last&.body.to_s)
  end

  test "the email job sends the digest and settles the delivery; a revoked token fails it" do
    bill
    run_at(taipei(2026, 10, 20, 8, 5))
    email = deliveries.find_by!(channel: "email")
    travel_to(taipei(2026, 10, 20, 8, 6)) { perform_enqueued_jobs }
    assert_equal "sent", email.reload.status
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @alex.email_address ], mail.to
    assert_match "今天到期", mail.body.to_s

    email.update!(status: "pending")
    ActionMailer::Base.add_delivery_method :revoked, RevokedToken
    ReminderMailer.delivery_method = :revoked
    DeliverReminderJob.perform_now(email.id)
    assert_equal [ "failed", "invalid_grant" ], email.reload.values_at(:status, :error)
  ensure
    ReminderMailer.delivery_method = :test
  end

  class RevokedToken
    def initialize(*) = nil
    def deliver!(*) = raise(DeliveryMethods::GmailApi::AuthorizationError, "invalid_grant")
  end

  test "a delivery stuck in pending for 2 hours is dispatched again" do
    stuck = ReminderDelivery.create!(household: @home, user: @alex, channel: "email", run_on: Date.new(2026, 10, 20), created_at: 3.hours.ago)
    assert_enqueued_with(job: DeliverReminderJob, args: [ stuck.id ]) { Reminders::Run.call }
  end
end
