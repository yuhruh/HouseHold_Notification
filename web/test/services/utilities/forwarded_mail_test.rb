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
    def done!(id, bill: nil) = @done[id] = bill
  end

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    ForwardingInbox.define_singleton_method(:mailbox) { "household.bills@gmail.com" }
    @account = @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"))
    @inbox = @home.reload.forwarding_inbox
    @inbox.update!(allowed_senders: [ "coowner@gmail.com" ])
    @address = @inbox.address
  end

  teardown { ForwardingInbox.singleton_class.send(:remove_method, :mailbox) }

  # `sent`: headers the sender wrote themselves, which Gmail keeps below its own
  def email(from:, subject: "Hello", body: "Hi", to: @address, return_path: nil, auth: nil, content_type: "text/plain", sent: [])
    caf = "#{to.sub("@", "=")}@gmail.com"
    headers = [ "Delivered-To: #{to}",
      ("Return-Path: <#{return_path.sub("CAF", caf)}>" if return_path),
      ("Authentication-Results: mx.google.com; #{auth.gsub("CAF", caf)}" if auth),
      "Authentication-Results: spoofed.example; spf=pass smtp.mailfrom=nobody@example.com",
      *sent.map { it.gsub("CAF", caf) },
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

  # Forwarded by hand by the owner: From them, signed by their mail provider, 台電's email quoted inside
  def by_hand(from: "alex@example.com", quoted: "寄件者： 台灣電力公司 <ebill@taipower.com.tw>", signed: from.split("@").last)
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
    assert_equal({ "m1" => nil }, inbox.done)
    @inbox.reload
    assert_equal [ LINK, nil, "co.owner@gmail.com" ], [ @inbox.forwarding_link, @inbox.forwarding_code, @inbox.forwarding_from ]
    assert @inbox.pending_confirmation?
    assert_equal({ "kind" => "forwarding_request", "detail" => "co.owner@gmail.com" }, @account.reload.activity.first.except("at"))

    travel 8.days do
      assert_not @inbox.pending_confirmation?, "a week-old request isn't shown"
    end
  end

  test "a confirmation Google didn't sign, or from someone who isn't a member, is ignored and says why" do
    read_mail("m1" => confirmation(auth: "dkim=fail header.i=@google.com"), "m2" => confirmation(requester: "stranger@gmail.com"),
      "m3" => email(from: "forwarding-noreply@google.com", auth: "dkim=pass header.i=@google.com", body: "co.owner@gmail.com wants something"))
    assert_nil @inbox.reload.forwarding_link
    assert_equal [ [ "not_authentic", "forwarding-noreply@google.com" ], [ "not_member", "stranger@gmail.com" ], [ "no_confirmation", nil ] ],
      @account.reload.activity.reverse.map { it.values_at("reason", "detail") }
  end

  test "a 台電 email forwarded by hand by the owner is accepted for the bill reader, but doesn't count as the filter working" do
    inbox = FakeInbox.new("m1" => by_hand, "m2" => by_hand(quoted: "From: 台灣電力公司 <ebill@taipower.com.tw>"))
    assert_equal %i[bill bill], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => :taipower, "m2" => :taipower }, inbox.done)
    @account.reload
    assert_equal [ { "kind" => "received_by_hand", "detail" => "alex@example.com" }, { "kind" => "unreadable", "detail" => "Fwd: 台電電子帳單" } ],
      @account.activity.first(2).reverse.map { it.except("at") }, "no bill table in it, so the reader says so"
    assert_nil @account.last_success_at
  end

  test "a hand-forward that isn't 台電's, or isn't really from the member, is ignored" do
    assert_equal %i[ignored ignored], read_mail("m1" => by_hand(quoted: "From: Shop <news@shop.example>"), "m2" => by_hand(signed: "evil.example"))
    assert_equal [ [ "not_taipower_forward", "alex@example.com" ], [ "not_authentic", "alex@example.com" ] ],
      @account.reload.activity.reverse.map { it.values_at("reason", "detail") }
  end

  test "a 台電 email forwarded by an allowed Gmail is accepted (dots don't matter) and labelled for the bill reader" do
    @inbox.update!(forwarding_link: LINK, forwarding_code_at: 1.minute.ago)
    inbox = FakeInbox.new("m1" => taipower)
    assert_equal [ :bill ], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => :taipower }, inbox.done)
    @account.reload
    assert @account.connected?
    assert_equal({ "kind" => "received", "detail" => "co.owner@gmail.com" }, @account.activity.second.except("at"))
    assert_not @inbox.reload.pending_confirmation?, "once mail arrives the request has done its job"
    assert @inbox.confirmed?
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
    mail = email(from: "alex@example.com", subject: "Fwd: 台電e-Bill115年10月電費通知(電號:12345678901)", content_type: "text/html",
      auth: "dkim=pass header.i=@example.com; spf=pass smtp.mailfrom=alex@example.com", body:)
    assert_difference(-> { @home.records.count }, 1) { assert_equal [ :bill ], read_mail("m1" => mail) }
    assert_equal [ "2026 7月-8月", 1234 ], @home.records.last.then { [ it.period.to_s, it.amount_required ] }
    assert_nil @account.reload.last_success_at
  end

  test "a member's own Gmail is accepted too" do
    @inbox.update!(allowed_senders: [])
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

  FORWARDED = "---------- Forwarded message ---------\nFrom: 台灣電力公司 <ebill@taipower.com.tw>\n\n電號 04-08-1234-56-7".freeze

  test "only the owner and co-owners add bills by forwarding by hand; a viewer or an added email uses a filter" do
    viewer = users(:google_only)
    results = read_mail("added" => by_hand(from: "co.owner@gmail.com"), "viewer" => by_hand(from: viewer.email_address))
    assert_equal %i[ignored ignored], results
    assert_equal [ [ "by_hand_not_editor", "co.owner@gmail.com" ], [ "by_hand_not_editor", viewer.email_address ] ],
      @account.reload.activity.reverse.map { it.values_at("reason", "detail") }
    assert_equal 0, @home.records.count

    memberships(:sam_home).update!(role: "co_owner")
    assert_equal [ :bill ], read_mail("coowner" => by_hand(from: viewer.email_address))
    assert_equal [ :bill ], read_mail("filter" => taipower), "the added email's Gmail filter still forwards 台電's own emails"
  end

  test "an envelope sender written to read like a DKIM pass doesn't make the owner's hand-forward authentic" do
    sender = "x.dkim=pass.header.d=example.com@evil.example"
    forged = email(from: "alex@example.com", subject: "Fwd: 台電電子帳單", body: FORWARDED, return_path: sender,
      auth: "spf=pass (google.com: domain of #{sender} designates 6.6.6.6 as permitted sender) smtp.mailfrom=#{sender}; " \
        "dmarc=fail (p=NONE sp=QUARANTINE dis=NONE) header.from=example.com")
    assert_equal [ :ignored ], read_mail("m1" => forged)
    assert_equal [ "not_authentic", "alex@example.com" ], @account.reload.activity.first.values_at("reason", "detail")
  end

  test "an envelope sender with quotes or brackets in it proves nothing, whatever the header then seems to say" do
    sender = "\"x) ; dkim=pass header.i=@example.com ; (y\"@evil.example"
    forged = email(from: "alex@example.com", subject: "Fwd: 台電電子帳單", body: FORWARDED, return_path: sender,
      auth: "spf=pass (google.com: domain of #{sender} designates 6.6.6.6 as permitted sender) smtp.mailfrom=#{sender}")
    assert_equal [ :ignored ], read_mail("m1" => forged)
    assert_equal "not_authentic", @account.reload.activity.first["reason"]
  end

  test "headers the sender wrote to pass for Gmail's own don't count" do
    by_hand = email(from: "alex@example.com", subject: "Fwd: 台電電子帳單", body: FORWARDED, return_path: "someone@evil.example",
      auth: "dkim=pass header.i=@evil.example; spf=pass smtp.mailfrom=someone@evil.example",
      sent: [ "Authentication-Results: mx.google.com; dkim=pass header.i=@example.com" ])
    filtered = email(from: "台灣電力公司 <ebill@taipower.com.tw>", body: "電號 04-08-1234-56-7", return_path: "someone@evil.example",
      auth: "spf=pass smtp.mailfrom=someone@evil.example",
      sent: [ "Return-Path: <co.owner+caf_=CAF>", "Authentication-Results: mx.google.com; spf=pass smtp.mailfrom=\"co.owner+caf_=CAF\"" ])
    assert_equal %i[ignored ignored], read_mail("m1" => by_hand, "m2" => filtered)
    assert_equal %w[not_authentic unknown_forwarder], @account.reload.activity.reverse.map { it["reason"] }
    assert_nil @account.last_success_at
  end

  test "a subject the database can't store is still handled, so the mail after it is read" do
    inbox = FakeInbox.new("m1" => by_hand.sub(/^Subject: .*$/, "Subject: =?UTF-8?B?AAAA?="), "m2" => confirmation)
    assert_equal %i[bill confirm], Utilities::ForwardedMail.call(inbox:)
    assert_equal %w[m1 m2], inbox.done.keys
    assert_equal [ "unreadable", "" ], @account.reload.activity.second.values_at("kind", "detail")
  end

  test "a message that can't be handled is reported and labelled, and doesn't hold up the others" do
    Utilities::Taipower::Reader.define_singleton_method(:call) { |*| raise "the reader broke" }
    inbox = FakeInbox.new("m1" => by_hand, "m2" => confirmation)
    assert_equal %i[failed confirm], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => nil, "m2" => nil }, inbox.done)
    assert_equal LINK, @inbox.reload.forwarding_link
  ensure
    Utilities::Taipower::Reader.singleton_class.send(:remove_method, :call)
  end

  test "mail to an address whose ledger number doesn't match its token is left alone, but still labelled" do
    wrong = @address.sub("+h#{@home.id}-", "+h#{@home.id + 1}-")
    inbox = FakeInbox.new("m1" => email(from: "ebill@taipower.com.tw", to: wrong))
    assert_equal [ :unknown ], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => nil }, inbox.done)
    assert_empty @account.reload.activity
  end

  test "nothing is read without the app's Gmail, or once neither Electricity nor Water is on" do
    assert_empty Utilities::ForwardedMail.call(inbox: nil)
    @account.destroy!
    assert_nil @home.reload.forwarding_inbox, "the address stops working"
    inbox = FakeInbox.new("m1" => taipower)
    assert_empty Utilities::ForwardedMail.call(inbox:)
    assert_nil inbox.asked
  end

  def water_html(name) = File.read(Rails.root.join("test/fixtures/files/twwater/#{name}.html"))

  # 台水's email as a Gmail filter delivers it to the same address as 台電's
  def water(subject:, name:, forwarder: "co.owner")
    email(from: "台灣自來水公司 <service@ebillserver.water.gov.tw>", subject:, content_type: "text/html", body: water_html(name),
      return_path: "#{forwarder}+caf_=CAF",
      auth: "dkim=pass header.i=@ebillserver.water.gov.tw; spf=pass (google.com: domain of #{forwarder}+caf_=CAF designates 1.2.3.4) smtp.mailfrom=\"#{forwarder}+caf_=CAF\"; dmarc=pass")
  end

  test "台水's bill and paid notice reach Water through the same address, labelled for 台水" do
    water_category = @home.categories.find_by!(name_zh: "水費")
    water_account = @home.create_water_account!(category: water_category)
    assert_equal @inbox, @home.reload.forwarding_inbox, "Water shares Electricity's address"
    open_bill = @home.records.create!(record_type: "expense", category: water_category, details: "水費", period: Period.parse(2026, "7月-8月"))

    inbox = FakeInbox.new("m1" => water(subject: "台灣自來水公司115年10月帳單通知", name: "bill_notice"),
      "m2" => water(subject: "台灣自來水公司繳費成功通知", name: "paid_notice"))
    assert_equal %i[bill bill], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => :water, "m2" => :water }, inbox.done)
    assert_equal [ 680, Date.new(2026, 10, 21), true ], open_bill.reload.values_at(:amount_required, :due_on, :settled)

    water_account.reload
    assert water_account.connected?
    assert_equal "12345678901", water_account.customer_code
    assert_equal Date.new(2026, 10, 1), water_account.last_bill_on
    assert_equal Date.new(2026, 12, 1), water_account.next_mail_expected_on
    assert_nil @account.reload.last_success_at, "Electricity's filter status is its own"
    assert_empty @account.activity
  end

  test "a 台水 email is ignored while Water isn't on, and Electricity's activity says so" do
    assert_equal [ :ignored ], read_mail("m1" => water(subject: "台灣自來水公司115年10月帳單通知", name: "bill_notice"))
    assert_equal [ "not_turned_on", "台水" ], @account.reload.activity.first.values_at("reason", "detail")
    assert_equal 0, @home.records.count
  end

  test "a 台水 bill forwarded by hand is read too" do
    water_account = @home.create_water_account!(category: @home.categories.find_by!(name_zh: "水費"))
    body = "<div>---------- Forwarded message ---------<br>\nFrom: 台灣自來水公司 &lt;service@ebillserver.water.gov.tw&gt;<br>" \
      "Subject: 台灣自來水公司115年10月帳單通知</div>#{water_html("bill_notice")}"
    mail = email(from: "alex@example.com", subject: "Fwd: 台灣自來水公司115年10月帳單通知", content_type: "text/html",
      auth: "dkim=pass header.i=@example.com; spf=pass smtp.mailfrom=alex@example.com", body:)
    assert_equal [ :bill ], read_mail("m1" => mail)
    assert_equal [ "2026 7月-8月", 680 ], @home.records.last.then { [ it.period.to_s, it.amount_required ] }
    assert_nil water_account.reload.last_success_at
  end

  test "the job only logs when Gmail can't be read yet" do
    Utilities::Inbox.define_singleton_method(:connect) { raise Google::Apis::ClientError, "insufficientPermissions" }
    assert_nothing_raised { PollUtilityMailJob.perform_now }
  ensure
    Utilities::Inbox.singleton_class.send(:remove_method, :connect)
  end
end
