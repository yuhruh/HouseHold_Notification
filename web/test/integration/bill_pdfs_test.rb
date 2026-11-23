require "test_helper"

class BillPdfsTest < ActionDispatch::IntegrationTest
  include BillPdfSample

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @phone = @home.categories.find_by!(record_type: "expense", name_zh: "網路/電信")
    sign_in_as users(:alex)
  end

  def read(words = cht_words) = post(household_bill_pdf_path(@home), params: { words: words.to_json }, as: :json)

  test "New Record offers Choose Bill PDF on the same card, and a place for the auto-pay note" do
    get new_household_record_path(@home)
    assert_select "[data-controller=bill-scan] [data-action='bill-scan#choosePdf']", /選擇 PDF 帳單/
    assert_select "[data-controller=bill-scan] input[type=file][accept*=pdf]"
    assert_select "[data-bill-scan-target=autopay][hidden]"
  end

  test "the first 中華電信 bill asks once which category it is (網路/電信 offered); then the form values come back" do
    read
    body = response.parsed_body
    assert_equal [ true, true, false, "T19683736", "中華電信", @phone.id ], body.values_at("ok", "learned", "known", "biller", "biller_name", "suggested_category_id")
    assert_equal [ 1299, "2026-11-10", 2026, [ 9, 10 ], [ "9/16", "10/15" ] ], body.values_at("amount", "due_on", "period_year", "period_months", "period_note")
    assert_equal [ "中華電信", "用戶號碼 Y123456", "1200000000001", "定期付款" ], body.values_at("title", "details", "bill_number", "autopay")
    assert_nil body["category_id"]

    post household_biller_codes_path(@home), params: { code: "T19683736", category_id: @phone.id, deadline_offset_days: 0 }
    assert_response :no_content
    read
    assert_equal [ true, @phone.id, nil ], response.parsed_body.values_at("known", "category_id", "match")
  end

  test "the same bill read twice is already recorded; one typed in by hand for the period is similar" do
    @home.biller_codes.create!(code: "T19683736", category: @phone)
    by_hand = @home.records.create!(record_type: "expense", category: @phone, title: "中華電信", period: Period.parse(2026, "10月"))
    read
    assert_equal "similar", response.parsed_body["match"]
    assert_includes response.parsed_body["matches"], household_record_path(@home, by_hand)

    patch household_bill_scan_path(@home), params: { record_id: by_hand.id, bill_number: "1200000000001" }
    assert_response :no_content
    read
    assert_equal "already", response.parsed_body["match"]
  end

  test "a bill it hasn't learned comes back read by its labels, with no title or category to ask" do
    read(words([ [ "應繳金額：NT$864", 100, 200, 300, 24 ], [ "繳費截止日：2026/12/05", 600, 200, 320, 24 ] ]))
    body = response.parsed_body
    assert_equal [ true, false, true, 864, "2026-12-05", nil, nil, nil ], body.values_at("ok", "learned", "known", "amount", "due_on", "title", "biller", "period_months")
  end

  test "a PDF with no bill in it is refused" do
    read(words([ [ "電子發票證明聯 總計 120", 100, 100, 300, 24 ] ]))
    assert_response :unprocessable_content
    assert_equal false, response.parsed_body["ok"]
  end
end
