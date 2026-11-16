require "test_helper"

# Add a receipt › Invoice PDF end to end: pdf.js (public/vendor) reads the PDF in the browser and only
# its text reaches the review screen
class SupplyReceiptTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  test "an invoice PDF is read in the browser and its items listed for review" do
    home = households(:home)
    paper = home.supplies.create!(name: "Toilet paper", unit: "roll", level: 2, level_at: Time.current)
    sign_in
    visit scan_household_supplies_path(home, mode: "pdf")
    find("input[type=file][accept*=pdf]", visible: :all).attach_file(file_fixture("einvoice/acme_invoice.pdf"), make_visible: true)
    assert_selector "li", text: "acme_invoice.pdf", wait: 15
    assert_selector "li span", text: "Read ✓", wait: 15
    click_on "Review items ›"

    within "section#invoice_0" do
      assert_selector "input[name='invoices[0][store]'][value='ACME Store']"
      assert_selector "select[name='invoices[0][lines][0][choice]'] option[selected][value='#{paper.id}']"
      assert_selector "input[name='invoices[0][lines][0][quantity]'][value='2']"
      assert_selector "select[name='invoices[0][lines][1][choice]'] option[selected][value='skip']"
    end
    click_on "Save"
    assert_text "Saved 1 purchase from 1 invoice", wait: 10
    assert_equal 4, paper.reload.level
  end

  test "a printed receipt shows how many of its two QR codes are read, not boxes to tick" do
    sign_in
    visit scan_household_supplies_path(households(:home), mode: "receipt")
    assert_text "0 of 2 QR codes read"
    assert_text "Left QR · still needed"
    assert_selector "a[aria-current=page]", text: "Printed receipt"
  end
end
