require "test_helper"

class SuppliesBackTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  # ‹ Back to Supplies leads to the Supplies view the item was opened from (the tab, a search), also
  # after the item's own pages; opened from somewhere else, to Supplies as it opens (To Buy)
  test "Back to Supplies returns to the tab or search the item was opened from" do
    home = households(:home)
    supply = home.supplies.create!(name: "Toilet paper", unit: "roll", level: 40, level_at: Time.current, guess_days_per_unit: 3)
    item = household_supply_path(home, supply)
    back = "a[data-supplies-view-target=link]"
    sign_in

    visit household_supplies_path(home, tab: "all")
    find("li#row_supply_#{supply.id} a.btn-press[href='#{item}']").click
    assert_selector "h1", text: "Toilet paper"
    find(back).click
    assert_current_path household_supplies_path(home, tab: "all")

    supply.favorites.create!(user: users(:alex))
    visit household_supplies_path(home, tab: "favorites")
    find("li#card_supply_#{supply.id} a.btn-press[href='#{item}']").click
    assert_selector "h1", text: "Toilet paper"
    visit new_household_supply_purchase_path(home, supply)
    find(back).click
    assert_current_path household_supplies_path(home, tab: "favorites")

    visit household_supplies_path(home, q: "Toilet")
    find("li#row_supply_#{supply.id} a.btn-press[href='#{item}']").click
    assert_selector "h1", text: "Toilet paper"
    find(back).click
    assert_current_path household_supplies_path(home, q: "Toilet")

    visit household_records_path(home)
    visit item
    assert_selector "h1", text: "Toilet paper"
    find(back).click
    assert_current_path household_supplies_path(home)
  end
end
