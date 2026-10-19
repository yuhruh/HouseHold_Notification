require "test_helper"

class PushTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @alex = users(:alex)
    water = @home.categories.find_by!(name_zh: "水費")
    @record = @home.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "9月-10月"),
      amount_required: 580, due_on: Date.new(2026, 10, 20))
    @calls = []
  end

  def subscription_params(endpoint = "https://fcm.googleapis.com/fcm/send/abc")
    { subscription: { endpoint:, keys: { p256dh: "BNcR", auth: "tBHI" } } }
  end

  def push_delivery
    delivery = ReminderDelivery.create!(household: @home, user: @alex, channel: "web_push", run_on: Date.new(2026, 10, 20))
    ReminderLog.create!(record: @record, user: @alex, kind: "due_today", channel: "web_push", scheduled_on: Date.new(2026, 10, 20), reminder_delivery: delivery)
    delivery
  end

  # Stands in for WebPush.payload_send; returns 201 unless told to raise
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

  test "subscribing upserts by endpoint and reassigns the browser to whoever is signed in" do
    sign_in_as @alex
    post push_subscriptions_path, params: subscription_params, as: :json, headers: { "User-Agent" => "Mozilla/5.0 (Linux; Android 17) Chrome/155" }
    assert_response :created
    sub = PushSubscription.sole
    assert_equal [ @alex, "Android · Chrome" ], [ sub.user, sub.device_label ]
    sign_out
    sign_in_as users(:google_only)
    post push_subscriptions_path, params: subscription_params, as: :json
    assert_equal users(:google_only), PushSubscription.sole.user
  end

  test "explicit sign-out removes the browser's subscription; session expiry keeps it" do
    sign_in_as @alex
    post push_subscriptions_path, params: subscription_params, as: :json
    session = Current.session
    Session.where(id: session.id).delete_all # what the expiry cleanup does
    assert_nil PushSubscription.sole.session_id

    sign_in_as @alex
    post push_subscriptions_path, params: subscription_params("https://fcm.googleapis.com/fcm/send/def"), as: :json
    delete session_path
    assert_equal [ "https://fcm.googleapis.com/fcm/send/abc" ], PushSubscription.pluck(:endpoint)
  end

  test "a push digest goes to every device, waits for the receipt, and the receipt marks it sent" do
    @alex.push_subscriptions.create!(endpoint: "https://push/1", p256dh: "a", auth: "b", device_label: "Android · Chrome")
    delivery = push_delivery
    travel_to(Time.find_zone!("Asia/Taipei").local(2026, 10, 20, 8, 5)) { with_push { DeliverReminderJob.perform_now(delivery.id) } }
    assert_equal "awaiting_receipt", delivery.reload.status
    payload = JSON.parse(@calls.sole[:message])
    assert_match "我的家：1 筆帳單需要處理", payload["title"]
    assert_match "今天到期", payload["body"]
    assert_equal "high", @calls.sole[:urgency]

    post payload["receipt_url"]
    assert_response :no_content
    assert_equal "sent", delivery.reload.status
    assert @alex.push_subscriptions.sole.last_receipt_at
    post payload["receipt_url"]
    assert_response :not_found, "single use"
  end

  test "lock-screen privacy hides names and amounts" do
    @alex.update!(push_show_amounts: false)
    @alex.push_subscriptions.create!(endpoint: "https://push/1", p256dh: "a", auth: "b")
    with_push { DeliverReminderJob.perform_now(push_delivery.id) }
    assert_equal "打開 App 查看需要處理的帳單。", JSON.parse(@calls.sole[:message])["body"]
  end

  test "no device fails at once; a 410 deletes the subscription and fails" do
    delivery = push_delivery
    DeliverReminderJob.perform_now(delivery.id)
    assert_equal [ "failed", "no device has notifications enabled" ], delivery.reload.values_at(:status, :error)

    @alex.push_subscriptions.create!(endpoint: "https://push/gone", p256dh: "a", auth: "b")
    delivery.update!(status: "pending")
    gone = WebPush::ExpiredSubscription.new(Struct.new(:code, :body).new("410", ""), "push")
    with_push(error: gone) { DeliverReminderJob.perform_now(delivery.id) }
    assert_equal "failed", delivery.reload.status
    assert_empty @alex.push_subscriptions.reload
  end

  test "no receipt within 24h fails the delivery; the owner can send it by email instead" do
    @alex.push_subscriptions.create!(endpoint: "https://push/1", p256dh: "a", auth: "b", device_label: "Pixel · Chrome")
    delivery = push_delivery
    with_push { DeliverReminderJob.perform_now(delivery.id) }
    travel 25.hours do
      ConfirmPushReceiptsJob.perform_now
    end
    assert_equal "failed", delivery.reload.status
    assert_match "Pixel · Chrome: no confirmation in 24h", delivery.delivery_attempts.sole.error

    sign_in_as @alex
    get household_reminder_deliveries_path(@home)
    assert_select "button", "改用 Email 傳送"
    assert_enqueued_emails 1 do
      post send_by_email_household_reminder_delivery_path(@home, delivery)
    end
    assert_equal "resolved", delivery.reload.status
  end

  test "devices are listed in My account and can be removed" do
    sign_in_as @alex
    sub = @alex.push_subscriptions.create!(endpoint: "https://push/1", p256dh: "a", auth: "b", device_label: "Mac · Chrome")
    get account_path
    assert_select "#devices li", /Mac · Chrome/
    delete push_subscription_path(sub)
    assert_empty @alex.push_subscriptions.reload
  end

  test "the owner can remove a member's device; others can't" do
    device = users(:google_only).push_subscriptions.create!(endpoint: "https://push/lost", p256dh: "a", auth: "b", device_label: "Android · Chrome")
    sign_in_as users(:google_only)
    delete household_member_device_path(@home, device)
    assert_response :forbidden
    sign_out
    sign_in_as @alex
    get household_members_path(@home)
    assert_select "span", /Android · Chrome/
    delete household_member_device_path(@home, device)
    assert_not PushSubscription.exists?(device.id)
  end
end
