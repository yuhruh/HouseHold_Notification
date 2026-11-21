require "test_helper"

# After Used 1 or Undo, Supplies' lists put themselves in order without a page refresh (supplies-order)
class SupplyReorderTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 900 ]

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  # An item with its starting count, as New item saves it (Undo goes back to the count before)
  def supply(name, unit, level, days_per_unit)
    households(:home).supplies.create!(name:, unit:, level:, level_at: Time.current, guess_days_per_unit: days_per_unit).tap do
      Supplies::RecordCount.call(it, level, user: users(:alex))
    end
  end

  # Dish soap runs out in ~20 days and Toilet paper in ~24, both OK. One pack fewer and Toilet paper
  # runs out in ~12 days: Restock soon, so it belongs above Dish soap and on To Buy
  test "All: Used 1 moves the row to its new place and counts it on To Buy; Undo moves it back" do
    home = households(:home)
    soap = supply("Dish soap", "bottle", 1, 20)
    paper = supply("Toilet paper", "pack", 2, 12)
    to_buy_count = "nav.tab-row a[href$='tab=to_buy'] span.rounded-full"
    sign_in

    visit household_supplies_path(home, tab: "all")
    assert_selector "#row_supply_#{soap.id} ~ #row_supply_#{paper.id}"
    assert_no_selector to_buy_count

    find("button[aria-label='Used 1 pack: Toilet paper']").click
    assert_selector "#row_supply_#{paper.id} ~ #row_supply_#{soap.id}", wait: 5
    assert_selector "#row_supply_#{paper.id}", text: "Restock soon"
    assert_selector to_buy_count, text: "1"
    assert_selector "#supply_toast", text: "Used 1 · 1 pack left"

    within("#supply_toast") { click_on "Undo" }
    assert_selector "#row_supply_#{soap.id} ~ #row_supply_#{paper.id}", wait: 5
    assert_no_selector to_buy_count
    assert_selector "#supply_toast", text: "Undone · 2 packs left"
  end

  # Oat milk has ~12 days left: buy within 7 days. One box fewer and it is past its buy-by date
  test "To Buy: Used 1 moves the card up to Out Or Buy Now and the group headings follow" do
    home = households(:home)
    milk = supply("Oat milk", "box", 2, 6)
    sign_in

    visit household_supplies_path(home, tab: "to_buy")
    assert_selector "h2", text: "Buy In The Next 7 Days (1)"
    assert_no_selector "h2", text: "Out Or Buy Now"

    find("button[aria-label='Used 1 box: Oat milk']").click
    assert_selector "h2", text: "Out Or Buy Now (1)", wait: 5
    assert_no_selector "h2", text: "Buy In The Next 7 Days"
    assert_selector "#card_supply_#{milk.id}", text: "Restock now · 1 box left"
    assert_selector "#supply_toast", text: "Used 1 · 1 box left"
  end
end
