require "test_helper"

class SupplyAlertsJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  setup do
    @home = households(:home)
    @alex = users(:alex) # owner; google_only is a viewer
    travel_to Time.zone.local(2026, 11, 14, 9)
    @home.supplies.create!(name: "Shampoo", kind: "toiletries", unit: "bottle", level: 1, guess_days_per_unit: 5)
    @calls = []
  end

  teardown { travel_back }

  def notices = Notification.where(kind: "supplies")

  def with_push(error: nil)
    calls = @calls
    original = WebPush.method(:payload_send)
    WebPush.define_singleton_method(:payload_send) do |**args|
      calls << args
      raise error if error
      Struct.new(:code).new("201")
    end
    yield
  ensure
    WebPush.define_singleton_method(:payload_send, original)
  end

  test "one digest to each owner and co-owner, none to viewers, and only once" do
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/1", p256dh: "a", auth: "b")
    assert_no_enqueued_emails { with_push { SupplyAlertsJob.perform_now } }
    notice = notices.sole
    assert_equal @alex, notice.user
    assert_match "Shampoo", notice.body
    assert_equal "/h/#{@home.id}/supplies?tab=to_buy", notice.url
    assert_equal 1, @calls.size
    assert_no_difference(-> { notices.count }) { with_push { SupplyAlertsJob.perform_now } }
  end

  test "email when push is off, when there's no device, or when every device is gone" do
    assert_enqueued_email_with SupplyAlertsMailer, :digest, params: ->(p) { p[:notification] == notices.last } do
      SupplyAlertsJob.perform_now
    end

    @home.supplies.create!(name: "Soap", kind: "cleaning", unit: "bottle", level: 0, guess_days_per_unit: 5)
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/gone", p256dh: "a", auth: "b")
    gone = WebPush::ExpiredSubscription.new(Struct.new(:code, :body).new("410", ""), "push")
    assert_enqueued_emails(1) { with_push(error: gone) { SupplyAlertsJob.perform_now } }

    @home.supplies.create!(name: "Rice", kind: "food_drink", unit: "bag", level: 0, guess_days_per_unit: 5)
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/2", p256dh: "a", auth: "b")
    NotificationPreference.for(memberships(:alex_home)).update!(web_push: false)
    @calls.clear
    assert_enqueued_emails(1) { with_push { SupplyAlertsJob.perform_now } }
    assert_empty @calls
  end

  test "a push no device confirms within an hour is emailed, once" do
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/1", p256dh: "a", auth: "b")
    with_push { SupplyAlertsJob.perform_now }
    travel(30.minutes) { assert_no_enqueued_emails { ConfirmPushReceiptsJob.perform_now } }
    travel(61.minutes) do
      assert_enqueued_emails(1) { ConfirmPushReceiptsJob.perform_now }
      assert_no_enqueued_emails { ConfirmPushReceiptsJob.perform_now }
    end
  end

  test "members can turn supply alerts off" do
    NotificationPreference.for(memberships(:alex_home)).update!(supply_alert: false)
    SupplyAlertsJob.perform_now
    assert_empty notices
  end
end
