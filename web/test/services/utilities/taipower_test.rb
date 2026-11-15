require "test_helper"

class Utilities::TaipowerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Taipower = Utilities::Taipower
  TODAY = Date.new(2026, 10, 20)

  # 台電's own HTML from a real household's two emails (電號 12345678901, NT$1,234, address masked)
  BILL_SUBJECT = "台電e-Bill115年10月電費通知(電號:12345678901)".freeze
  PAID_SUBJECT = "台電e-Bill 115年10月電費已繳通知(電號：12345678901)".freeze

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @power = @home.categories.find_by!(name_zh: "電費")
    @account = @home.create_electricity_account!(category: @power)
  end

  def html(name) = File.read(Rails.root.join("test/fixtures/files/taipower/#{name}.html"))

  # As a Gmail filter delivers it: 台電's message itself, HTML only
  def taipower_mail(name, subject:, swap: {})
    body = swap.reduce(html(name)) { |text, (from, to)| text.gsub(from, to) }
    Mail.new do
      from "台電電子帳單服務系統 <ebill@ebppsmtp.taipower.com.tw>"
      self.subject = subject
      html_part do
        content_type "text/html; charset=UTF-8"
        self.body = body
      end
    end
  end

  def bill_notice(subject: BILL_SUBJECT, **) = taipower_mail("bill_notice", subject:, **)
  def paid_notice(subject: PAID_SUBJECT, **) = taipower_mail("paid_notice", subject:, **)

  def read(mail) = Taipower::Reader.call(@account, mail, today: TODAY)

  def bill(label, year: 2026, **attrs)
    @home.records.create!(record_type: "expense", category: @power, details: "電費", period: Period.parse(year, label), **attrs)
  end

  test "the bill notice and the paid notice are read from 台電's table, and both are the same 7月-8月 bill" do
    notice = Taipower::Parser.call(bill_notice)
    assert_equal [ "12345678901", Date.new(2026, 10, 1), 1234, Date.new(2026, 10, 28), false ],
      notice.to_h.values_at(:customer_code, :month, :amount, :due_on, :paid)
    assert_equal "2026 7月-8月", notice.period.to_s, "the 115年10月 bill is the one always entered as 7月-8月"

    paid = Taipower::Parser.call(paid_notice)
    assert_equal [ "12345678901", 1234, nil, true ], paid.to_h.values_at(:customer_code, :amount, :due_on, :paid)
    assert_equal notice.ref("12345678901"), paid.ref("12345678901")
  end

  test "periods across the year boundary" do
    jan = Taipower::Parser.call(bill_notice(subject: "台電e-Bill116年1月電費通知(電號:12345678901)"))
    feb = Taipower::Parser.call(bill_notice(subject: "台電e-Bill116年2月電費通知(電號:12345678901)"))
    assert_equal [ "2026 10月-11月", "2026 11月-12月" ], [ jan.period.to_s, feb.period.to_s ]
  end

  test "a hand-forward Gmail turned into plain text is read too, from its text" do
    text = "---------- Forwarded message ---------\nFrom: 台電電子帳單服務系統 <ebill@ebppsmtp.taipower.com.tw>\n" \
      "Subject: 台電e-Bill115年10月電費通知(電號:12345678901)\n\n簡易帳單資訊如下：\n\n" \
      "電 號 收費日 應繳總金額 繳費期限 代收截止日 查核碼\n12345678901 115/10/8 1,234 115/10/28 115/12/2 123\n用電地址 臺＊市"
    mail = Mail.new(subject: "Fwd: #{BILL_SUBJECT}", body: text, content_type: "text/plain; charset=UTF-8")
    assert_equal [ 1234, Date.new(2026, 10, 28) ], Taipower::Parser.call(mail).to_h.values_at(:amount, :due_on)
  end

  test "anything that isn't one of the two notices, or whose table is off, is not a bill" do
    assert_nil Taipower::Parser.call(Mail.new(subject: "台電節電活動", body: "<p>省電小撇步</p>", content_type: "text/html; charset=UTF-8"))
    assert_nil Taipower::Parser.call(bill_notice(swap: { "115/10/28" => "115/13/40" })), "no real 繳費期限"
    assert_nil Taipower::Parser.call(bill_notice(swap: { "12345678901" => "1234" })), "not an 11-digit 電號"
    assert_nil Taipower::Parser.call(bill_notice(subject: "台電e-Bill", swap: { "115年10月" => "" })), "no billing month"
  end

  test "the bill notice fills in the bill entered ahead, sets the 電號, and the paid notice marks it paid" do
    open_bill = bill("7月-8月")
    lines = read(bill_notice)
    open_bill.reload
    assert_equal [ 1234, Date.new(2026, 10, 28), false, "taipower:12345678901:2026-10" ],
      [ open_bill.amount_required, open_bill.due_on, open_bill.settled, open_bill.external_ref ]
    assert_equal [ "matched" ], lines.map { it["kind"] }
    assert_equal "taipower_synced", RecordEvent.where(record_id: open_bill.id).order(:id).last.action
    @account.reload
    assert_equal "12345678901", @account.customer_code
    assert_equal({ "kind" => "customer_code_set", "detail" => "…8901" }, @account.activity.last.except("at"))
    assert_nil @account.last_success_at, "only a filter-forwarded email counts as the filter working"

    assert_enqueued_with(job: NotifyBillsPaidJob, args: [ @home.id, [ open_bill.id ] ]) { read(paid_notice) }
    open_bill.reload
    assert open_bill.settled
    assert_equal [ 1234, TODAY, "台電 Email 確認繳費" ], [ open_bill.amount_paid, open_bill.paid_on, open_bill.payment_note ]
    assert_equal "taipower_paid", RecordEvent.where(record_id: open_bill.id).order(:id).last.action
  end

  test "with no bill yet the notice adds it; a paid notice with no bill adds it already paid; neither twice" do
    assert_difference -> { @home.records.count }, 1 do
      read(bill_notice)
      read(bill_notice)
    end
    added = @home.records.last
    assert_equal [ "2026 7月-8月", 1234, Date.new(2026, 10, 28), @power ], [ added.period.to_s, added.amount_required, added.due_on, added.category ]

    lines = assert_difference(-> { @home.records.count }, 1) { read(paid_notice(subject: PAID_SUBJECT.sub("10月", "8月"))) }
    assert_equal [ "added_paid" ], lines.map { it["kind"] }
    paid = @home.records.find(lines.first["record_id"])
    assert paid.settled
    assert_equal [ "2026 5月-6月", nil, TODAY ], [ paid.period.to_s, paid.due_on, paid.paid_on ]
    assert_equal %w[taipower_synced taipower_paid], RecordEvent.where(record_id: paid.id).order(:id).pluck(:action)
  end

  test "an amount that isn't 台電's is only reported, and a bill already paid is left alone" do
    differs = bill("7月-8月", amount_required: 999)
    read(bill_notice)
    assert_equal 999, differs.reload.amount_required
    assert_equal "amount_differs", @account.reload.activity.first["kind"]

    differs.update!(amount_required: 1234, amount_paid: 1234, paid_on: Date.new(2026, 10, 16))
    assert_no_enqueued_jobs(only: NotifyBillsPaidJob) { read(paid_notice) }
    assert_equal Date.new(2026, 10, 16), differs.reload.paid_on
  end

  test "once the 電號 is set, a bill for another 電號 is ignored; one another ledger uses isn't taken" do
    @account.update!(customer_code: "99999999999")
    assert_no_difference(-> { @home.records.count }) { assert_nil read(bill_notice) }
    assert_equal [ "other_customer_code", "…8901" ], @account.reload.activity.first.values_at("reason", "detail")

    @account.update!(customer_code: nil)
    other = households(:parents)
    Categories::Seed.call(other)
    other.create_electricity_account!(category: other.categories.find_by!(name_zh: "電費"), customer_code: "12345678901")
    assert_nil read(bill_notice)
    assert_nil @account.reload.customer_code
    assert_equal "other_ledger_code", @account.activity.first["reason"]
  end

  test "a 台電 email that isn't a bill is listed as unreadable and changes nothing" do
    mail = Mail.new(subject: "台電節電活動", body: "<p>省電小撇步</p>", content_type: "text/html; charset=UTF-8")
    assert_no_difference(-> { @home.records.count }) { assert_nil read(mail) }
    assert_equal({ "kind" => "unreadable", "detail" => "台電節電活動" }, @account.reload.activity.first.except("at"))
  end
end
