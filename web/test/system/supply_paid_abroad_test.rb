require "test_helper"

# Restock in another currency (paid_currency_controller): the NT$ amounts follow the price, the date,
# Paid with and the Card fee as they are typed
class SupplyPaidAbroadTest < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  setup do
    @home = households(:home)
    @supply = @home.supplies.create!(name: "Face Wash", unit: "piece", level: 2, level_at: Time.current)
    @day = @home.today - 2
    ExchangeRate.create!(base: "JPY", quote: "TWD", rated_on: @day, published_on: @day, rate: "0.20612", fetched_at: Time.current)
    ExchangeRate.create!(base: "JPY", quote: "TWD", rated_on: @home.today, published_on: @home.today, rate: "0.21", fetched_at: Time.current)
    # Anything else isn't to be had: the rate service is never asked from a test
    @fetch = Supplies::ExchangeRateLookup.method(:fetch)
    Supplies::ExchangeRateLookup.define_singleton_method(:fetch) { |_url| nil }
  end

  teardown { Supplies::ExchangeRateLookup.define_singleton_method(:fetch, @fetch) }

  def sign_in
    visit new_session_path
    find("input[type=email]").set("alex@example.com")
    find("input[type=password]").set("password123")
    find("form[action='#{session_path}'] [type=submit]", match: :first).click
    assert_no_selector "input[type=password]", wait: 10
  end

  # The menu is a see-through <select> over the three letters: chosen the way a tap on it would
  def choose_currency(code)
    execute_script("const menu = document.querySelector('#supply_purchase_paid_currency'); menu.value = arguments[0]; menu.dispatchEvent(new Event('change', { bubbles: true }))", code)
  end

  def amount(name) = find("input[name='supply_purchase[#{name}]']").value

  test "yen by card: both amounts follow the price, the date and the card fee; one typed over stays; cash has one amount" do
    sign_in
    visit new_household_supply_purchase_path(@home, @supply)
    assert_no_selector "[data-paid-currency-target='panel']"
    assert_selector "[data-paid-currency-target='code']", text: "TWD"

    find("#supply_purchase_quantity").set("2")
    choose_currency "JPY"
    assert_selector "[data-paid-currency-target='code']", text: "JPY"
    find("#supply_purchase_total_price").set("1196")
    # Today's rate to begin with
    assert_text "JP¥1 = NT$0.21 · rate for #{@home.today.strftime("%b %-d, %Y")}", wait: 5
    assert_equal %w[251 255], [ amount("home_total"), amount("home_total_with_fee") ]

    find("#supply_purchase_purchased_on").set(@day)
    assert_text "JP¥1 = NT$0.2061 · rate for #{@day.strftime("%b %-d, %Y")}", wait: 5
    assert_text "The rate is for the day you bought it, not today. Change the date and it follows."
    assert_equal %w[247 250], [ amount("home_total"), amount("home_total_with_fee") ]
    assert_text "With the 1.5% card fee"
    assert_text "The one you choose is saved: NT$125 a piece."
    assert_checked_field "supply_purchase_card_fee_included_1"
    take_screenshot

    find("#supply_purchase_card_fee_percent").set("3")
    assert_text "With the 3% card fee"
    assert_equal %w[247 254], [ amount("home_total"), amount("home_total_with_fee") ]
    assert_text "The one you choose is saved: NT$127 a piece."

    find("#supply_purchase_home_total_with_fee").set("252")
    assert_text "You typed NT$252, so the app's NT$254 isn't used. That is NT$126 a piece."
    find("#supply_purchase_card_fee_percent").set("2")
    assert_equal "252", amount("home_total_with_fee"), "typed: it stays"
    take_screenshot
    click_on "Use the app's figure: NT$251"
    assert_equal "251", amount("home_total_with_fee")
    assert_no_button "Use the app's figure"

    find("label", text: "Without the card fee").click
    assert_text "The one you choose is saved: NT$124 a piece."

    find("label", text: "Cash", exact_text: true).click
    assert_no_selector "#supply_purchase_card_fee_percent"
    assert_no_selector "#supply_purchase_home_total_with_fee"
    assert_no_text "Without the card fee"
    assert_text "Amount in NT$"
    assert_no_text "Amount in NT$ to save"
    assert_text "No card fee. That is NT$124 a piece."
    assert_equal "247", amount("home_total")
    take_screenshot

    find("label", text: "Credit card", exact_text: true).click
    find("#supply_purchase_card_fee_percent").set("1.5")
    find("label", text: "With the 1.5% card fee").click
    assert_equal "250", amount("home_total_with_fee")
    find("#supply_purchase_store").set("松本清")
    click_on "Save"
    assert_text "+2 pieces · NT$250 (JP¥1,196) · 松本清", wait: 5
    purchase = @supply.purchases.sole
    assert_equal [ 250, "JPY", 1196, BigDecimal("0.20612"), "card", BigDecimal("1.5"), true, @day ],
                 purchase.values_at(:total_price, :paid_currency, :paid_total, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included, :purchased_on)
  end

  test "at home nothing in the panel is sent; with no rate the form asks for the amount and still saves" do
    sign_in
    visit new_household_supply_purchase_path(@home, @supply)
    find("#supply_purchase_quantity").set("1")
    choose_currency "USD"
    assert_text "The rate for USD couldn't be fetched just now. Type the NT$ amount to save, or try again.", wait: 5
    assert_selector "[data-paid-currency-target='panel'].bg-amber-50"
    assert_button "Try again"
    assert_selector "#supply_purchase_home_total[required]"
    assert_no_selector "#supply_purchase_card_fee_percent"
    assert_no_selector "#supply_purchase_home_total_with_fee"
    assert_equal "0.01", find("#supply_purchase_total_price")[:step]
    take_screenshot

    find("#supply_purchase_total_price").set("18.99")
    find("#supply_purchase_home_total").set("635")
    click_on "Save"
    assert_text "NT$635", wait: 5
    assert_equal [ 635, "USD", BigDecimal("18.99"), nil, "card", nil, nil ],
                 @supply.purchases.sole.values_at(:total_price, :paid_currency, :paid_total, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)

    visit new_household_supply_purchase_path(@home, @supply)
    choose_currency "USD"
    assert_button "Try again", wait: 5
    choose_currency "TWD"
    assert_no_selector "[data-paid-currency-target='panel']"
    assert_equal "1", find("#supply_purchase_total_price")[:step]
    find("#supply_purchase_quantity").set("1")
    find("#supply_purchase_total_price").set("169")
    click_on "Save"
    assert_text "NT$169", wait: 5
    assert_equal [ 169, nil, nil, nil ], @supply.purchases.order(:id).last.values_at(:total_price, :paid_currency, :paid_total, :paid_by)
  end
end
