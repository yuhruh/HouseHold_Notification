require "test_helper"

class BillsPaidNotificationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @alex = users(:alex) # owner
    @gas = @home.categories.find_by!(name_zh: "瓦斯費")
    @calls = []
  end

  def paid_bill(label, amount)
    @home.records.create!(record_type: "expense", category: @gas, details: "瓦斯費", period: Period.parse(2026, label),
      amount_required: amount, due_on: Date.new(2026, 10, 20), amount_paid: amount, paid_on: Date.new(2026, 10, 18))
  end

  def notices = Notification.where(kind: "bills_paid")

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

  test "BillSync tells members once, after the bills are saved, about every bill it marked paid" do
    account = @home.create_gas_account!(customer_code: "1234567890", category: @gas)
    open_bills = [ "5月-6月", "7月-8月" ].map do |label|
      @home.records.create!(record_type: "expense", category: @gas, details: "瓦斯費", period: Period.parse(2026, label))
    end
    paid = [ [ "5月-6月", Date.new(2026, 8, 20), 410 ], [ "7月-8月", Date.new(2026, 10, 20), 374 ] ].map do |label, due_on, amount|
      Data.define(:due_on, :amount, :period) { def ref(code) = "test:#{code}:#{due_on}" }.new(due_on, amount, Period.parse(2026, label))
    end
    sync = -> { Utilities::BillSync.new(account, today: Date.new(2026, 11, 14), note: "test", events: { synced: :gas_synced, paid: :gas_paid }).call(paid:) }

    assert_enqueued_with(job: NotifyBillsPaidJob, args: [ @home.id, open_bills.map(&:id) ]) { sync.call }
    assert_no_enqueued_jobs(only: NotifyBillsPaidJob) { sync.call } # already paid: nothing new
  end

  test "an owner with a device gets one inbox item and one push listing the bills, and no email" do
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/1", p256dh: "a", auth: "b")
    bills = [ paid_bill("5月-6月", 410), paid_bill("7月-8月", 374) ]
    assert_no_enqueued_emails do
      with_push { NotifyBillsPaidJob.perform_now(@home.id, bills.map(&:id)) }
    end

    notice = notices.sole
    assert_equal @alex, notice.user, "the viewer doesn't get it by default"
    assert_equal "我的家：2 筆帳單已繳費", notice.title
    assert_match "2026 7月-8月 · NT$374：已自動確認繳費（2026-10-18）", notice.body
    assert_equal "/h/#{@home.id}/records?category_id=#{@gas.id}&status=paid", notice.url
    payload = JSON.parse(@calls.sole[:message])
    assert_equal [ notice.title, notice.body ], payload.values_at("title", "body")
    assert_equal "normal", @calls.sole[:urgency]
    assert_nil notice.reload.fallback_emailed_at

    post payload["receipt_url"]
    assert_response :no_content
    assert notice.delivery_attempts.sole.received?
    travel(2.hours) { assert_no_enqueued_emails { ConfirmPushReceiptsJob.perform_now } }
  end

  test "with no device, or every device gone, the push falls back to email at once" do
    bill = paid_bill("7月-8月", 374)
    assert_enqueued_email_with BillsPaidMailer, :paid, params: ->(p) { p[:notification] == notices.last } do
      NotifyBillsPaidJob.perform_now(@home.id, [ bill.id ])
    end
    assert notices.sole.fallback_emailed_at

    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/gone", p256dh: "a", auth: "b")
    gone = WebPush::ExpiredSubscription.new(Struct.new(:code, :body).new("410", ""), "push")
    assert_enqueued_emails(1) { with_push(error: gone) { NotifyBillsPaidJob.perform_now(@home.id, [ bill.id ]) } }
    assert_empty @alex.push_subscriptions.reload
  end

  test "a push no device confirms within an hour is emailed, once" do
    @alex.push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/1", p256dh: "a", auth: "b")
    with_push { NotifyBillsPaidJob.perform_now(@home.id, [ paid_bill("7月-8月", 374).id ]) }

    travel(30.minutes) { assert_no_enqueued_emails { ConfirmPushReceiptsJob.perform_now } }
    travel(61.minutes) do
      assert_enqueued_emails(1) { ConfirmPushReceiptsJob.perform_now }
      assert_no_enqueued_emails { ConfirmPushReceiptsJob.perform_now }
    end
  end

  test "members can turn it off, viewers can turn it on, and email off means no fallback" do
    bill = paid_bill("7月-8月", 374)
    NotificationPreference.for(memberships(:alex_home)).update!(bill_paid: false)
    NotificationPreference.for(memberships(:sam_home)).update!(bill_paid: true, email: false, web_push: false)
    assert_no_enqueued_emails { NotifyBillsPaidJob.perform_now(@home.id, [ bill.id ]) }
    assert_equal [ users(:google_only) ], notices.map(&:user)

    sign_in_as @alex
    patch account_notification_preference_path(@home.id), params: { notification_preference: { email: "1", web_push: "1", bill_paid: "1" } }
    assert NotificationPreference.for(memberships(:alex_home)).bill_paid
  end

  test "the email lists the bills with a link" do
    bill = paid_bill("7月-8月", 374)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { NotifyBillsPaidJob.perform_now(@home.id, [ bill.id ]) }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "alex@example.com" ], mail.to
    assert_equal "我的家：1 筆帳單已繳費", mail.subject
    assert_match "/h/#{@home.id}/records/#{bill.id}", mail.text_part&.body&.to_s || mail.body.to_s
  end
end
