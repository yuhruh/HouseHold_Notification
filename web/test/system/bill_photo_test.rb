require "test_helper"

# New Record › Use a Photo without barcodes: the photo is read for its text on the device (Tesseract under
# public/vendor), and only the words reach bill_pdfs#create. photo.png is the sample 中華電信 bill drawn
# by test/fixtures/files/cht_bill/photo.html (made-up name and numbers)
class BillPhotoTest < ActionDispatch::SystemTestCase
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

  def use_photo(name)
    find("[data-bill-scan-target=photo]", visible: :all).attach_file(file_fixture("cht_bill/#{name}"), make_visible: true)
  end

  test "a bill photo without barcodes is read for its text: numbers please check, title and category from photo" do
    @home.biller_codes.create!(code: "T19683736", category: @phone)
    sign_in
    visit new_household_record_path(@home)
    use_photo("photo.png")

    assert_text "Filled in from the photo", wait: 90 # the reader loads (about 5 MB) and reads the photo
    assert_text "Photos can be misread: check each amber field against the bill."
    assert_equal [ @phone.id.to_s, "中華電信", "用戶號碼 Y123456", "1299", "2026-11-10", "2026", "9", "10" ],
      %w[record_category_id record_title record_details record_amount_required record_due_on record_period_year record_period_start_month record_period_end_month].map { find("##{it}").value }
    assert_selector "label[for=record_title] [data-scan-tag]", text: "from photo"
    assert_selector "label[for=record_amount_required] [data-scan-tag]", text: "please check"
    assert_selector "label[for=record_due_on] [data-scan-tag]", text: "please check"
    assert_equal "1200000000001", find("#record_bill_number", visible: :all).value
    take_screenshot
  end

  test "a photo with no readable text says so" do
    sign_in
    visit new_household_record_path(@home)
    # A reader that finds nothing (Tesseract isn't loaded when window.Tesseract is already there)
    execute_script(<<~JS)
      window.Tesseract = { createWorker: async () => ({ recognize: async () => ({ data: { lines: [] } }) }) }
    JS
    use_photo("photo.png")

    assert_text "Couldn't read an amount due and a due date in this photo.", wait: 15
    assert_equal "", find("#record_amount_required").value
  end
end
