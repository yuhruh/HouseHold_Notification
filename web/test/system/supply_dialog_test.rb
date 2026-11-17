require "test_helper"

class SupplyDialogTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  # Turbo prefetches a link on hover; the prefetch must already ask for the "modal" frame, or the
  # click reuses a whole page and the dialog stays empty until a second click
  test "Edit opens the dialog on the first click after hovering" do
    home = households(:home)
    supply = home.supplies.create!(name: "Toilet paper", unit: "roll", level: 4, level_at: Time.current)
    sign_in
    visit household_supply_path(home, supply)
    link = find("a[href='#{edit_household_supply_path(home, supply)}']")
    link.hover
    sleep 0.6 # let Turbo's hover prefetch finish
    link.click
    assert_selector "dialog[open]", wait: 5
  end

  test "New item: choosing New category shows a field for its name, and saving makes the category with the item" do
    home = households(:home)
    sign_in
    visit new_household_supply_path(home)
    assert_no_selector "#new_category_name"
    select "＋ New category…", from: "supply_supply_category_id"
    assert_selector "#new_category_name:focus[required]"
    select "Kitchen", from: "supply_supply_category_id"
    assert_no_selector "#new_category_name"
    select "＋ New category…", from: "supply_supply_category_id"
    find("#new_category_name").set("Shampoo")
    find("#supply_name").set("Lux")
    find("#supply_level").set("2")
    click_on "Save"
    assert_text "piece · Shampoo", wait: 5
    assert_equal "Shampoo", home.supplies.find_by!(name: "Lux").category.name_en, "typed in English, so it's the English name"
  end

  test "using the last one pops up Time to restock; Bought more opens the purchase dialog" do
    home = households(:home)
    supply = home.supplies.create!(name: "Toilet paper", unit: "roll", level: 1, level_at: Time.current)
    sign_in
    visit household_supply_path(home, supply)
    find("button[aria-label='Used 1 roll: Toilet paper']").click
    within("dialog[open]", wait: 5) do
      assert_text "Toilet paper"
      click_on "Later"
    end
    assert_no_selector "dialog[open]"
    assert_selector "button[disabled][aria-label='Used 1 roll: Toilet paper']"

    Supplies::RecordCount.call(supply, 1, user: users(:alex))
    visit household_supply_path(home, supply)
    find("button[aria-label='Used 1 roll: Toilet paper']").click
    within("dialog[open]", wait: 5) { find("a[href='#{new_household_supply_purchase_path(home, supply)}']").click }
    assert_selector "dialog[open] input[name='supply_purchase[quantity]']", wait: 5
  end

  test "Edit: Combine moves an item into another as a brand, and Delete removes one; both ask first" do
    home = households(:home)
    alex = users(:alex)
    promise = home.supplies.create!(name: "Promise Volume Shampoo", unit: "bottle", level: 0, level_at: Time.current)
    shampoo = home.supplies.create!(name: "Shampoo", unit: "bottle", level: 0, level_at: Time.current)
    Supplies::LogPurchase.call(promise, { quantity: 2, total_price: 499, purchased_on: home.today }, user: alex)
    Supplies::LogPurchase.call(shampoo, { quantity: 3, total_price: 897, purchased_on: home.today - 5, product_name: "PDRN Care" }, user: alex)
    sign_in
    visit household_supply_path(home, promise)
    click_on "Edit"
    within("dialog[open]", wait: 5) { click_on "Combine with another item" }
    assert_text "Combine with which item?", wait: 5
    asked = dismiss_confirm { find("button", text: /\AShampoo/).click }
    assert_match "Shampoo will have 2 + 3 = 5 bottles", asked
    assert Supply.exists?(promise.id), "Cancel changes nothing"
    accept_confirm { find("button", text: /\AShampoo/).click }
    assert_text "Combined Promise Volume Shampoo into Shampoo.", wait: 5
    assert_text "5 bottles now"
    assert_text "In stock by brand"

    click_on "Edit"
    asked = within("dialog[open]", wait: 5) { accept_confirm { click_on "Delete item" } }
    assert_match "Delete Shampoo for good? Its history (2 purchases)", asked
    assert_text "Deleted Shampoo.", wait: 5
    assert_equal 0, home.supplies.count
  end
end
