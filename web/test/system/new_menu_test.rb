require "test_helper"

class NewMenuTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  def click_at(x, y)
    page.driver.browser.action.move_to_location(x.round, y.round).click.perform
  end

  # The tab bar's New opens the Add new sheet: Cancel or a click anywhere outside the sheet closes it,
  # a click on the sheet itself (its padding) doesn't
  test "the Add new sheet closes on Cancel or a click outside it" do
    sign_in
    visit household_records_path(households(:home))
    open_sheet = -> { find("#tab-bar button[aria-haspopup=dialog]").click }
    sheet = "#tab-bar dialog[open]"

    open_sheet.call
    within(sheet) { click_on "Cancel" }
    assert_no_selector sheet

    open_sheet.call
    box = evaluate_script("document.querySelector('#{sheet}').getBoundingClientRect().toJSON()")
    click_at box["left"] + 5, box["top"] + 5
    assert_selector sheet

    click_at 200, box["top"] - 100
    assert_no_selector sheet
  end
end
