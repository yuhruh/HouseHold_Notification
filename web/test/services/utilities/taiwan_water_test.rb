require "test_helper"

class Utilities::TaiwanWaterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Water = Utilities::TaiwanWater
  TODAY = Date.new(2026, 10, 20)

  # 台水's own HTML from a real household's two emails (水號 12345678901, NT$680, address masked)
  BILL_SUBJECT = "台灣自來水公司115年10月帳單通知".freeze
  PAID_SUBJECT = "台灣自來水公司繳費成功通知".freeze

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @account = @home.create_water_account!(category: @water)
  end

  def html(name) = File.read(Rails.root.join("test/fixtures/files/twwater/#{name}.html"))

  # As a Gmail filter delivers it: 台水's message itself, HTML only
  def water_mail(name, subject:, swap: {})
    body = swap.reduce(html(name)) { |text, (from, to)| text.gsub(from, to) }
    Mail.new do
      from "台灣自來水公司 <service@ebillserver.water.gov.tw>"
      self.subject = subject
      html_part do
        content_type "text/html; charset=UTF-8"
        self.body = body
      end
    end
  end

  def bill_notice(subject: BILL_SUBJECT, **) = water_mail("bill_notice", subject:, **)
  def paid_notice(subject: PAID_SUBJECT, **) = water_mail("paid_notice", subject:, **)

  def read(mail) = Water::Reader.call(@account, mail, today: TODAY)

  test "the bill notice and the paid notice are read from 台水's tables, and both are the same 7月-8月 bill" do
    notice = Water::Parser.call(bill_notice)
    assert_equal [ "12345678901", Date.new(2026, 10, 1), 680, Date.new(2026, 10, 21), false, Date.new(2026, 10, 1) ],
      notice.to_h.values_at(:customer_code, :month, :amount, :due_on, :paid, :issued_on)
    assert_equal "2026 7月-8月", notice.period.to_s, "the 115年10月 bill (meter read late August) is 7月-8月"

    paid = Water::Parser.call(paid_notice)
    assert_equal [ "12345678901", Date.new(2026, 10, 1), 680, nil, true ], paid.to_h.values_at(:customer_code, :month, :amount, :due_on, :paid)
    assert_equal "twwater:12345678901:2026-10", paid.ref("12345678901")
    assert_equal notice.ref("12345678901"), paid.ref("12345678901")
  end

  test "a hand-forward Gmail turned into plain text is read too" do
    text = "---------- Forwarded message ---------\nFrom: 台灣自來水公司 <service@ebillserver.water.gov.tw>\n" \
      "Subject: #{BILL_SUBJECT}\n\n115年10月水費帳單明細\n序號 水號 繳費起始日 應繳金額 繳費期限 代收期限 線上繳費連結 備註\n" \
      "1 12345678901 115/10/01 680 115/10/21 115/11/21 信用卡繳費\n<https://www.water.gov.tw/x>\n" \
      "網路繳費\n水號 代收期限 銷帳編號 應繳總金額 查核碼\n12345678901 1151121 00000000000000 00000680 3"
    mail = Mail.new(subject: "Fwd: #{BILL_SUBJECT}", body: text, content_type: "text/plain; charset=UTF-8")
    assert_equal [ 680, Date.new(2026, 10, 21), false ], Water::Parser.call(mail).to_h.values_at(:amount, :due_on, :paid)
  end

  test "anything that isn't one of the two notices, or whose table is off, is not a bill" do
    assert_nil Water::Parser.call(Mail.new(subject: "台灣自來水公司統一發票中獎通知", body: "<p>恭喜</p>", content_type: "text/html; charset=UTF-8"))
    assert_nil Water::Parser.call(bill_notice(swap: { "115/10/21" => "115/13/40" })), "no real 繳費期限"
    assert_nil Water::Parser.call(bill_notice(swap: { "12345678901" => "1234" })), "not an 11-digit 水號"
    assert_nil Water::Parser.call(paid_notice(swap: { "115年10月" => "" })), "no billing month"
  end

  test "the bill notice fills in the bill entered ahead, sets the 水號, and the paid notice marks it paid" do
    open_bill = @home.records.create!(record_type: "expense", category: @water, details: "水費", period: Period.parse(2026, "7月-8月"))
    assert_equal [ "matched" ], read(bill_notice).map { it["kind"] }
    open_bill.reload
    assert_equal [ 680, Date.new(2026, 10, 21), false ], [ open_bill.amount_required, open_bill.due_on, open_bill.settled ]
    assert_equal "water_synced", RecordEvent.where(record_id: open_bill.id).order(:id).last.action
    @account.reload
    assert_equal "12345678901", @account.customer_code
    assert_equal({ "kind" => "customer_code_set", "detail" => "…8901" }, @account.activity.last.except("at"))
    assert_equal Date.new(2026, 12, 1), @account.next_mail_expected_on

    assert_enqueued_with(job: NotifyBillsPaidJob, args: [ @home.id, [ open_bill.id ] ]) { read(paid_notice) }
    open_bill.reload
    assert open_bill.settled
    assert_equal [ 680, TODAY, "台水 Email 確認繳費" ], [ open_bill.amount_paid, open_bill.paid_on, open_bill.payment_note ]
    assert_equal "water_paid", RecordEvent.where(record_id: open_bill.id).order(:id).last.action
  end

  test "with no bill yet the notice adds it, never twice" do
    assert_difference(-> { @home.records.count }, 1) { 2.times { read(bill_notice) } }
    assert_equal [ "2026 7月-8月", 680, @water ], @home.records.last.then { [ it.period.to_s, it.amount_required, it.category ] }
  end

  test "once the 水號 is set, a bill for another 水號 is ignored" do
    @account.update!(customer_code: "99999999999")
    assert_no_difference(-> { @home.records.count }) { assert_nil read(bill_notice) }
    assert_equal [ "water_other_customer_code", "…8901" ], @account.reload.activity.first.values_at("reason", "detail")
  end

  test "a 台水 email that isn't a bill is listed as unreadable" do
    mail = Mail.new(subject: "台灣自來水公司統一發票中獎通知", body: "<p>恭喜</p>", content_type: "text/html; charset=UTF-8")
    assert_nil read(mail)
    assert_equal({ "kind" => "unreadable", "detail" => "台灣自來水公司統一發票中獎通知" }, @account.reload.activity.first.except("at"))
  end
end
