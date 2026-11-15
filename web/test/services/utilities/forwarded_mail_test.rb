require "test_helper"

class Utilities::ForwardedMailTest < ActiveSupport::TestCase
  # Messages as the app's Gmail would hold them, handed out by id; remembers what was labelled
  class FakeInbox
    attr_reader :done, :asked

    def initialize(messages)
      @messages = messages
      @done = {}
    end

    def unprocessed(addresses)
      @asked = addresses
      @messages.keys - @done.keys
    end

    def raw(id) = @messages.fetch(id)
    def done!(id, bill: false) = @done[id] = bill
  end

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    ElectricityAccount.define_singleton_method(:mailbox) { "household.bills@gmail.com" }
    @account = @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"), allowed_senders: [ "coowner@gmail.com" ])
    @address = @account.inbox_address
  end

  teardown { ElectricityAccount.singleton_class.send(:remove_method, :mailbox) }

  def email(from:, subject: "Hello", body: "Hi", to: @address, return_path: nil, auth: nil, content_type: "text/plain")
    caf = "#{to.sub("@", "=")}@gmail.com"
    headers = [ "Delivered-To: #{to}",
      ("Return-Path: <#{return_path.sub("CAF", caf)}>" if return_path),
      ("Authentication-Results: mx.google.com; #{auth.gsub("CAF", caf)}" if auth),
      "Authentication-Results: spoofed.example; spf=pass smtp.mailfrom=nobody@example.com",
      "From: #{from}", "To: someone@gmail.com", "Subject: #{Mail::Encodings.b_value_encode(subject, "UTF-8")}", "Content-Type: #{content_type}; charset=UTF-8" ].compact
    "#{headers.join("\r\n")}\r\n\r\n#{body.gsub("\n", "\r\n")}"
  end

  LINK = "https://mail-settings.google.com/mail/vf-%5BANGjdJ_abc%5D-aLp-ZWLp5C81DnQ0R".freeze

  # Shaped like the one Gmail really sent (Nov 2026): a confirmation link, no code
  def confirmation(requester: "co.owner@gmail.com", auth: "dkim=pass header.i=@google.com header.s=20260707")
    email(from: "Gmail Team <forwarding-noreply@google.com>", auth:,
      subject: "(Gmail Forwarding Confirmation - Receive Mail from #{requester}",
      body: "#{requester} has requested to automatically forward mail to\nyour email\naddress #{@address}.\n\n" \
        "To allow #{requester} to automatically forward mail to your address,\nplease click the link below to confirm the request:\n\n" \
        "#{LINK}\n\nIf you click the link and it appears to be broken, please copy and paste it\n...\n" \
        "click this link to cancel this verification:\nhttps://mail-settings.google.com/mail/uf-%5BANGjdJ_abc%5D-zzz\n")
  end

  # Forwarded by hand from a member's Gmail: From the member, signed by gmail.com, 台電's email quoted inside
  def by_hand(from: "co.owner@gmail.com", quoted: "寄件者： 台灣電力公司 <ebill@taipower.com.tw>", signed: "gmail.com")
    email(from:, subject: "Fwd: 台電電子帳單", auth: "dkim=pass header.i=@#{signed}; spf=pass smtp.mailfrom=#{from}",
      body: "---------- Forwarded message ---------\n#{quoted}\nDate: 2026年10月7日\nSubject: 電子帳單\n\n電號 04-08-1234-56-7")
  end

  # A 台電 email as Gmail's filter forwarding delivers it: the envelope sender is the forwarder's
  # "+caf_=" address, and Gmail's SPF check on arrival passed for it
  def taipower(forwarder: "co.owner", spf: "pass", from: "台灣電力公司 <ebill@taipower.com.tw>", dkim: "pass",
    subject: "Taipower e-bill", body: "電號 04-08-1234-56-7", content_type: "text/plain")
    email(from:, subject:, body:, content_type:,
      return_path: "#{forwarder}+caf_=CAF",
      auth: "dkim=#{dkim} header.i=@taipower.com.tw; spf=#{spf} (google.com: domain of #{forwarder}+caf_=CAF designates 1.2.3.4) smtp.mailfrom=\"#{forwarder}+caf_=CAF\"; dmarc=#{dkim == "pass" ? "pass" : "fail"}")
  end

  def read_mail(messages) = Utilities::ForwardedMail.call(inbox: FakeInbox.new(messages))

  test "Gmail's confirmation link is kept for the page's Confirm button, with who asked for it" do
    inbox = FakeInbox.new("m1" => confirmation)
    assert_equal [ :confirm ], Utilities::ForwardedMail.call(inbox:)
    assert_equal [ @address ], inbox.asked
    assert_equal({ "m1" => false }, inbox.done)
    @account.reload
    assert_equal [ LINK, nil, "co.owner@gmail.com" ], [ @account.forwarding_link, @account.forwarding_code, @account.forwarding_from ]
    assert @account.pending_forwarding_confirmation?
    assert_equal({ "kind" => "forwarding_request", "detail" => "co.owner@gmail.com" }, @account.activity.first.except("at"))

    travel 8.days do
      assert_not @account.pending_forwarding_confirmation?, "a week-old request isn't shown"
    end
  end

  test "a confirmation Google didn't sign, or from someone who isn't a member, is ignored and says why" do
    read_mail("m1" => confirmation(auth: "dkim=fail header.i=@google.com"), "m2" => confirmation(requester: "stranger@gmail.com"),
      "m3" => email(from: "forwarding-noreply@google.com", auth: "dkim=pass header.i=@google.com", body: "co.owner@gmail.com wants something"))
    @account.reload
    assert_nil @account.forwarding_link
    assert_equal [ [ "not_authentic", "forwarding-noreply@google.com" ], [ "not_member", "stranger@gmail.com" ], [ "no_confirmation", nil ] ],
      @account.activity.reverse.map { it.values_at("reason", "detail") }
  end

  test "a 台電 email forwarded by hand by a member is accepted for the bill reader, but doesn't count as the filter working" do
    inbox = FakeInbox.new("m1" => by_hand, "m2" => by_hand(quoted: "From: 台灣電力公司 <ebill@taipower.com.tw>"))
    assert_equal %i[bill bill], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => true, "m2" => true }, inbox.done)
    @account.reload
    assert_equal [ { "kind" => "received_by_hand", "detail" => "co.owner@gmail.com" }, { "kind" => "unreadable", "detail" => "Fwd: 台電電子帳單" } ],
      @account.activity.first(2).reverse.map { it.except("at") }, "no bill table in it, so the reader says so"
    assert_nil @account.last_success_at
  end

  test "a hand-forward that isn't 台電's, or isn't really from the member, is ignored" do
    assert_equal %i[ignored ignored], read_mail("m1" => by_hand(quoted: "From: Shop <news@shop.example>"), "m2" => by_hand(signed: "evil.example"))
    assert_equal [ [ "not_taipower_forward", "co.owner@gmail.com" ], [ "not_authentic", "co.owner@gmail.com" ] ],
      @account.reload.activity.reverse.map { it.values_at("reason", "detail") }
  end

  test "a 台電 email forwarded by an allowed Gmail is accepted (dots don't matter) and labelled for the bill reader" do
    @account.update!(forwarding_link: LINK, forwarding_code_at: 1.minute.ago)
    inbox = FakeInbox.new("m1" => taipower)
    assert_equal [ :bill ], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => true }, inbox.done)
    @account.reload
    assert @account.connected?
    assert_equal({ "kind" => "received", "detail" => "co.owner@gmail.com" }, @account.activity.second.except("at"))
    assert_not @account.pending_forwarding_confirmation?, "once mail arrives the request has done its job"
  end

  def taipower_html(name) = File.read(Rails.root.join("test/fixtures/files/taipower/#{name}.html"))

  test "a 台電 bill and paid notice forwarded by the filter are written into the ledger" do
    power = @account.category
    open_bill = @home.records.create!(record_type: "expense", category: power, details: "電費", period: Period.parse(2026, "7月-8月"))
    read_mail("m1" => taipower(from: "台電電子帳單服務系統 <ebill@ebppsmtp.taipower.com.tw>", content_type: "text/html",
      subject: "台電e-Bill115年10月電費通知(電號:12345678901)", body: taipower_html("bill_notice")))
    assert_equal [ 1234, Date.new(2026, 10, 28), false ], open_bill.reload.values_at(:amount_required, :due_on, :settled)
    @account.reload
    assert_equal "12345678901", @account.customer_code
    assert @account.connected?
    assert_equal %w[received customer_code_set matched], @account.activity.map { it["kind"] }.reverse

    read_mail("m2" => taipower(from: "台電電子帳單服務系統 <ebill@ebppsmtp.taipower.com.tw>", content_type: "text/html",
      subject: "台電e-Bill 115年10月電費已繳通知(電號：12345678901)", body: taipower_html("paid_notice")))
    assert open_bill.reload.settled
  end

  test "a 台電 bill forwarded by hand is written too, without counting as the filter working" do
    body = "<div>---------- Forwarded message ---------<br>\nFrom: 台電電子帳單服務系統 &lt;ebill@ebppsmtp.taipower.com.tw&gt;<br>" \
      "Subject: 台電e-Bill115年10月電費通知(電號:12345678901)</div>#{taipower_html("bill_notice")}"
    mail = email(from: "co.owner@gmail.com", subject: "Fwd: 台電e-Bill115年10月電費通知(電號:12345678901)", content_type: "text/html",
      auth: "dkim=pass header.i=@gmail.com; spf=pass smtp.mailfrom=co.owner@gmail.com", body:)
    assert_difference(-> { @home.records.count }, 1) { assert_equal [ :bill ], read_mail("m1" => mail) }
    assert_equal [ "2026 7月-8月", 1234 ], @home.records.last.then { [ it.period.to_s, it.amount_required ] }
    assert_nil @account.reload.last_success_at
  end

  test "a member's own Gmail is accepted too" do
    @account.update!(allowed_senders: [])
    users(:alex).update!(email_address: "alex.home@gmail.com")
    assert_equal [ :bill ], read_mail("m1" => taipower(forwarder: "alexhome"))
  end

  test "anything else is ignored, and says why" do
    results = read_mail(
      "a" => taipower(from: "Phisher <billing@taipower-tw.example>"),
      "b" => taipower(dkim: "fail"),
      "c" => taipower(spf: "softfail"),
      "d" => email(from: "ebill@taipower.com.tw", auth: "dkim=pass header.i=@taipower.com.tw"),
      "e" => taipower(forwarder: "stranger"))
    assert_equal %i[ignored] * 5, results
    reasons = @account.reload.activity.map { it.values_at("reason", "detail") }.reverse
    assert_equal [ [ "not_taipower", "billing@taipower-tw.example" ], [ "not_authentic", "ebill@taipower.com.tw" ],
      [ "unknown_forwarder", nil ], [ "unknown_forwarder", nil ], [ "not_member", "stranger@gmail.com" ] ], reasons
    assert_nil @account.last_success_at
  end

  test "mail to an address whose ledger number doesn't match its token is left alone, but still labelled" do
    wrong = @address.sub("+h#{@home.id}-", "+h#{@home.id + 1}-")
    inbox = FakeInbox.new("m1" => email(from: "ebill@taipower.com.tw", to: wrong))
    assert_equal [ :unknown ], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => false }, inbox.done)
    assert_empty @account.reload.activity
  end

  test "nothing is read without the app's Gmail, or without an electricity account" do
    assert_empty Utilities::ForwardedMail.call(inbox: nil)
    @account.destroy!
    inbox = FakeInbox.new("m1" => taipower)
    assert_empty Utilities::ForwardedMail.call(inbox:)
    assert_nil inbox.asked
  end

  test "the job only logs when Gmail can't be read yet" do
    Utilities::Inbox.define_singleton_method(:connect) { raise Google::Apis::ClientError, "insufficientPermissions" }
    assert_nothing_raised { PollUtilityMailJob.perform_now }
  ensure
    Utilities::Inbox.singleton_class.send(:remove_method, :connect)
  end
end
