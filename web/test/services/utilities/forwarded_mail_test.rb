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

  def email(from:, subject: "Hello", body: "Hi", to: @address, return_path: nil, auth: nil)
    caf = "#{to.sub("@", "=")}@gmail.com"
    headers = [ "Delivered-To: #{to}",
      ("Return-Path: <#{return_path.sub("CAF", caf)}>" if return_path),
      ("Authentication-Results: mx.google.com; #{auth.gsub("CAF", caf)}" if auth),
      "Authentication-Results: spoofed.example; spf=pass smtp.mailfrom=nobody@example.com",
      "From: #{from}", "To: someone@gmail.com", "Subject: #{subject}", "Content-Type: text/plain; charset=UTF-8" ].compact
    "#{headers.join("\r\n")}\r\n\r\n#{body.gsub("\n", "\r\n")}"
  end

  def confirmation(auth: "dkim=pass header.i=@google.com header.s=20230601")
    email(from: "Gmail Team <forwarding-noreply@google.com>", auth:,
      subject: "(#123456789) Gmail Forwarding Confirmation - Receive Mail from co.owner@gmail.com",
      body: "co.owner@gmail.com has requested to automatically forward mail to your email address\n#{@address}.\n\nConfirmation code: 123456789\n")
  end

  # A 台電 email as Gmail's filter forwarding delivers it: the envelope sender is the forwarder's
  # "+caf_=" address, and Gmail's SPF check on arrival passed for it
  def taipower(forwarder: "co.owner", spf: "pass", from: "台灣電力公司 <ebill@taipower.com.tw>", dkim: "pass")
    email(from:, subject: "Taipower e-bill", body: "電號 04-08-1234-56-7",
      return_path: "#{forwarder}+caf_=CAF",
      auth: "dkim=#{dkim} header.i=@taipower.com.tw; spf=#{spf} (google.com: domain of #{forwarder}+caf_=CAF designates 1.2.3.4) smtp.mailfrom=\"#{forwarder}+caf_=CAF\"; dmarc=#{dkim == "pass" ? "pass" : "fail"}")
  end

  def read_mail(messages) = Utilities::ForwardedMail.call(inbox: FakeInbox.new(messages))

  test "Gmail's confirmation code is kept for the page, with who asked for it" do
    inbox = FakeInbox.new("m1" => confirmation)
    assert_equal [ :code ], Utilities::ForwardedMail.call(inbox:)
    assert_equal [ @address ], inbox.asked
    assert_equal({ "m1" => false }, inbox.done)
    @account.reload
    assert_equal [ "123456789", "co.owner@gmail.com" ], [ @account.forwarding_code, @account.forwarding_from ]
    assert @account.pending_forwarding_code?
    assert_equal "forwarding_code", @account.activity.first["kind"]

    travel 8.days do
      assert_not @account.pending_forwarding_code?, "a week-old code isn't shown"
    end
  end

  test "a confirmation Gmail didn't sign is ignored" do
    assert_equal [ :ignored ], read_mail("m1" => confirmation(auth: "dkim=fail header.i=@google.com"))
    assert_nil @account.reload.forwarding_code
  end

  test "a 台電 email forwarded by an allowed Gmail is accepted (dots don't matter) and labelled for the bill reader" do
    @account.update!(forwarding_code: "123456789", forwarding_code_at: 1.minute.ago)
    inbox = FakeInbox.new("m1" => taipower)
    assert_equal [ :bill ], Utilities::ForwardedMail.call(inbox:)
    assert_equal({ "m1" => true }, inbox.done)
    @account.reload
    assert @account.connected?
    assert_equal({ "kind" => "received", "detail" => "co.owner@gmail.com" }, @account.activity.first.except("at"))
    assert_not @account.pending_forwarding_code?, "once mail arrives the code has done its job"
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
