require "test_helper"

class ReminderDeliveriesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @record = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "9月-10月"),
      amount_required: 580, due_on: Date.new(2026, 10, 20))
    @failed = ReminderDelivery.create!(household: @home, user: users(:google_only), channel: "email", run_on: Date.new(2026, 10, 20),
      status: "failed", error: "Invalid To header", attempts: 3)
    ReminderLog.create!(record: @record, user: users(:google_only), kind: "due_today", channel: "email",
      scheduled_on: Date.new(2026, 10, 20), reminder_delivery: @failed)
  end

  def taipei(*args) = Time.find_zone!("Asia/Taipei").local(*args)

  test "the owner gets one daily summary in-app (not by email when email is what failed)" do
    travel_to taipei(2026, 10, 20, 8, 10) do
      assert_no_enqueued_emails do
        OwnerFailureSummaryJob.perform_now
      end
      note = users(:alex).notifications.sole
      assert_match "1 則提醒未送達", note.title
      assert_match "Sam（Email：Invalid To header）", note.body
      assert @failed.reload.owner_notified_at
      assert_equal Date.new(2026, 10, 20), @home.reload.last_failure_summary_on
      OwnerFailureSummaryJob.perform_now
      assert_equal 1, users(:alex).notifications.count, "once a day"
    end
  end

  test "no summary before the owner's reminder hour" do
    travel_to taipei(2026, 10, 20, 7, 10) do
      OwnerFailureSummaryJob.perform_now
      assert_empty users(:alex).notifications
    end
  end

  test "the owner sees failures and resends; paid items are dropped, a fully paid digest resolves" do
    sign_in_as users(:alex)
    get household_reminder_deliveries_path(@home)
    assert_select "p.text-red-700", "Invalid To header"
    assert_enqueued_with(job: DeliverReminderJob, args: [ @failed.id, { resend: true } ]) do
      post resend_household_reminder_delivery_path(@home, @failed)
    end
    assert_equal [ "pending", users(:alex) ], [ @failed.reload.status, @failed.resent_by ]

    @failed.update!(status: "failed", resent_at: 11.minutes.ago)
    @record.update!(amount_paid: 580, paid_on: Date.new(2026, 10, 21))
    post resend_household_reminder_delivery_path(@home, @failed)
    assert_equal "resolved", @failed.reload.status
  end

  test "resend is limited to once per 10 minutes and the page is owner-only" do
    @failed.update!(resent_at: 2.minutes.ago)
    sign_in_as users(:alex)
    assert_no_enqueued_jobs(only: DeliverReminderJob) { post resend_household_reminder_delivery_path(@home, @failed) }
    sign_out
    sign_in_as users(:google_only)
    get household_reminder_deliveries_path(@home)
    assert_response :forbidden
  end
end
