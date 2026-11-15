require "test_helper"

class SupplyDialogTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  # Turbo prefetches a link on hover; the prefetch must already ask for the "modal" frame, or the
  # click reuses a whole page and the dialog stays empty until a second click
  test "Edit opens the dialog on the first click after hovering" do
    home = households(:home)
    supply = home.supplies.create!(name: "Toilet paper", unit: "roll", level: 4, level_at: Time.current)
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
    visit household_supply_path(home, supply)
    link = find("a[href='#{edit_household_supply_path(home, supply)}']")
    link.hover
    sleep 0.6 # let Turbo's hover prefetch finish
    link.click
    assert_selector "dialog[open]", wait: 5
  end
end
