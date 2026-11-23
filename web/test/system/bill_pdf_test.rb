require "test_helper"

# New Record › Choose Bill PDF end to end: pdf.js (public/vendor) reads the PDF in the browser, a locked
# one asks for its password in the card, and only the PDF's text reaches bill_pdfs#create. The test
# bills are made by test/fixtures/files/cht_bill/generate.rb
class BillPdfTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @phone = @home.categories.find_by!(record_type: "expense", name_zh: "網路/電信")
  end

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  def choose_pdf(name)
    find("[data-bill-scan-target=pdf]", visible: :all).attach_file(file_fixture("cht_bill/#{name}"), make_visible: true)
  end

  test "a 中華電信 bill PDF asks once for its category, fills in the form, and is known when chosen again" do
    sign_in
    visit new_household_record_path(@home)
    choose_pdf("cht_bill.pdf")

    assert_text "Bill read: 中華電信", wait: 15
    assert_equal @phone.id.to_s, find("#scan_category_id").value, "網路/電信 is offered"
    assert_no_text "What does the barcode deadline mean?"
    click_on "Fill In the Form"

    assert_text "Filled in from the PDF", wait: 10
    assert_equal [ @phone.id.to_s, "中華電信", "用戶號碼 Y123456", "1299", "2026-11-10", "2026", "9", "10" ],
      %w[record_category_id record_title record_details record_amount_required record_due_on record_period_year record_period_start_month record_period_end_month].map { find("##{it}").value }
    assert_selector "label[for=record_title] [data-scan-tag]", text: "from PDF"
    assert_selector "label[for=record_details] [data-scan-tag]", text: "please check"
    assert_text "The bill says 9/16 – 10/15"
    assert_text "This bill says 定期付款 (auto-pay). Record the payment once it's charged."
    take_screenshot

    click_on "Save", match: :first
    assert_text "中華電信", wait: 10
    record = @home.records.order(:id).last
    assert_equal [ "1200000000001", 1299, nil ], [ record.bill_number, record.amount_required.to_i, record.paid_on ]

    visit new_household_record_path(@home)
    choose_pdf("cht_bill.pdf")
    assert_text "Already in your records", wait: 15
    assert_selector "button", text: "Choose Another PDF"
  end

  test "a locked bill PDF asks for its password in the card" do
    @home.biller_codes.create!(code: "T19683736", category: @phone)
    sign_in
    visit new_household_record_path(@home)
    choose_pdf("cht_bill_locked.pdf")

    assert_text "This PDF is locked.", wait: 15
    assert_text "cht_bill_locked.pdf"
    find("[data-bill-scan-target=lockInput]").set("wrong")
    click_on "Open PDF"
    assert_text "Wrong password. Try again.", wait: 10
    find("[data-bill-scan-target=lockInput]").set("A123456789")
    click_on "Open PDF"

    assert_text "Filled in from the PDF", wait: 15
    assert_equal "1299", find("#record_amount_required").value
  end
end
