require "test_helper"

class SuppliesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    sign_in_as users(:alex)
  end

  def create_item(**attrs)
    @home.supplies.create!(name: "Toilet paper", kind: "toiletries", unit: "roll", level: 4, guess_days_per_unit: 3, **attrs)
  end

  test "add an item, use one, undo it, then log a purchase with Also add to Ledger" do
    get household_supplies_path(@home)
    assert_select "main div.text-center details summary", /新增第一項日用品/
    assert_select "main div.text-center details" do
      assert_select "a", 4
      assert_select "a:first-child[href=?]", new_household_supply_path(@home), text: /日用品項目/
      assert_select "a[href=?]", scan_household_supplies_path(@home), text: /掃描商品條碼/
      assert_select "a[href=?]", scan_household_supplies_path(@home, mode: "receipt"), text: /新增發票/
      assert_select "a[href=?]", restock_household_supplies_path(@home), text: /記錄購買/
      assert_select "a[href=?]", new_household_record_path(@home), 0
    end

    post household_supplies_path(@home), params: { supply: { name: "Toilet paper", kind: "toiletries", unit: "roll", level: 4, guess_days_per_unit: 3, lead_days: 3, alert_when_left: 0 } }
    supply = @home.supplies.sole
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 4 ], supply.counts.map(&:level)

    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    assert_response :success
    assert_match "turbo-stream action=\"replace\" target=\"#{ActionView::RecordIdentifier.dom_id(supply, :forecast)}\"", response.body
    assert_match "用掉 1 · 剩 3 捲", response.body
    assert_equal 3, supply.reload.level

    delete household_supply_count_path(@home, supply, supply.counts.order(:id).last), as: :turbo_stream
    assert_equal 4, supply.reload.level

    assert_difference -> { @home.records.count } do
      post household_supply_purchases_path(@home, supply), params: { add_to_ledger: "1",
        supply_purchase: { quantity: 12, total_price: 289, store: "Costco", purchased_on: @home.today, left_before: 4 } }
    end
    assert_redirected_to household_supply_path(@home, supply)
    record = @home.records.order(:id).last
    assert record.settled?
    assert_equal 289, record.amount_paid
    assert_equal "日用品", record.category.name_zh
    assert_equal 16, supply.reload.level

    get household_supply_path(@home, supply)
    assert_select "details summary", /去哪買/
    assert_match "NT$289 買 12 · 每捲 NT$24.1", response.body
    get household_supplies_path(@home, tab: "all")
    assert_select "li##{ActionView::RecordIdentifier.dom_id(supply, :row)}", /Toilet paper/
    # No add button of its own (like Bills): the header's New is the one place to add
    assert_select "main details summary", text: /新增日用品/, count: 0
    assert_select "header a[href=?]", new_household_supply_path(@home)
    assert_select "header a[href=?]", scan_household_supplies_path(@home)
  end

  test "−1 at 0 stays at 0, and the button is off" do
    supply = create_item(level: 0)
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    assert_equal 0, supply.reload.level
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉一個']"
  end

  test "using the last one turns −1 off and asks to restock" do
    supply = create_item(level: 1)
    Supplies::RecordCount.call(supply, 1, user: users(:alex))
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    assert_equal 0, supply.reload.level
    assert_match "dialog data-controller=\"modal\"", response.body
    assert_match "Toilet paper 用完了", response.body
    assert_match new_household_supply_purchase_path(@home, supply), response.body
    assert_match household_supply_count_path(@home, supply, supply.counts.order(:id).last), response.body
    assert_match(/<button[^>]*disabled[^>]*aria-label="Toilet paper 用掉一個"/, response.body)

    get household_supplies_path(@home, tab: "all")
    assert_select "div[title*='已經用完了'] button[disabled]"

    # Undo brings back the toast and −1
    delete household_supply_count_path(@home, supply, supply.counts.order(:id).last), as: :turbo_stream
    assert_no_match "dialog data-controller", response.body
    assert_equal 1, supply.reload.level
  end

  test "an estimate of nothing left also turns −1 off, and says to update the count if some are left" do
    supply = create_item(level: 2, guess_days_per_unit: 1, level_at: 3.days.ago)
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉一個']"
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: 1 } }, as: :turbo_stream
    assert_no_match "dialog data-controller", response.body
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉一個']", 0
  end

  test "negative or decimal counts and quantities are refused" do
    supply = create_item
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: "2.5" } }, as: :turbo_stream
    assert_response :unprocessable_content
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: "-1" } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_equal 4, supply.reload.level

    post household_supply_purchases_path(@home, supply), params: { supply_purchase: { quantity: "1.5", total_price: 10, purchased_on: @home.today, left_before: 0 } }
    assert_response :unprocessable_content
    post household_supplies_path(@home), params: { supply: { name: "Soap", kind: "cleaning", unit: "bottle", level: -2 } }
    assert_response :unprocessable_content
  end

  test "edit doesn't change the count; archive hides it and stops its alerts" do
    supply = create_item
    patch household_supply_path(@home, supply), params: { supply: { name: "TP", lead_days: 7, level: 99 } }
    assert_equal [ "TP", 7, 4 ], supply.reload.values_at(:name, :lead_days, :level)
    post archive_household_supply_path(@home, supply)
    assert supply.reload.archived_at
    get household_supplies_path(@home)
    assert_select "li##{ActionView::RecordIdentifier.dom_id(supply, :row)}", 0
    assert_select "a[href=?]", household_supplies_path(@home, archived: 1)
  end

  test "the stock bar's Total: with the unit on the item page, the number alone in the lists" do
    item = create_item(name: "Coffee", unit: "bottle", level: 9, guess_days_per_unit: 100)
    item.purchases.create!(household: @home, purchased_on: 10.days.ago.to_date, quantity: 24, total_price: 458, left_before: 1)
    empty = create_item(name: "Empty", level: 0)

    get household_supply_path(@home, item)
    assert_select "section#forecast_supply_#{item.id} p", text: /目前.*9 瓶.*總數：25 瓶/m
    assert_select "body[data-controller~=supplies-view][data-supplies-view-list-value=?]", household_supplies_path(@home)
    assert_select "a[data-supplies-view-target=link][href=?]", household_supplies_path(@home), text: /回到日用品/

    get household_supplies_path(@home, tab: "all")
    assert_select "li#row_supply_#{item.id} span", text: "總數：25"
    # The All list's Left column is the number alone; the unit is there for a screen reader
    assert_select "li#row_supply_#{item.id} span[aria-hidden=true]", text: "9"
    assert_select "li#row_supply_#{item.id} span.sr-only", text: "9 瓶"
    assert_select "li#row_supply_#{empty.id}", text: /總數/, count: 0
    assert_select "a[data-supplies-view-target]", 0

    get household_supplies_path(@home, tab: "stocked")
    assert_select "li#card_supply_#{item.id} span", text: "總數：25"
  end

  test "Favorites: each owner and co-owner has their own star, and the tab lists every starred item once with whose star it is" do
    alex, sam = users(:alex), users(:google_only)
    memberships(:sam_home).update!(role: "co_owner")
    coffee = create_item(name: "Coffee", unit: "bottle", level: 30)
    soap = create_item(name: "Soap", level: 30)
    plain = create_item(name: "Tissue", level: 30)

    get household_supplies_path(@home, tab: "favorites")
    assert_select "nav a[aria-current=page][href=?]", household_supplies_path(@home, tab: "favorites"), text: /我的最愛/
    assert_select "#supplies_favorites_count.hidden", text: "0"
    assert_select "main p", text: /還沒有我的最愛/
    assert_select "li[id^=card_]", 0
    assert_select "nav[aria-label=誰加的星]", 0

    # The star is on the cards (Stocked), the All rows and the item page
    get household_supplies_path(@home, tab: "stocked")
    assert_select "li#card_supply_#{coffee.id} form[action=?] button[aria-pressed=false]", household_supply_favorite_path(@home, coffee)
    get household_supplies_path(@home, tab: "all")
    assert_select "li#row_supply_#{coffee.id} form[action=?] button[aria-label=?]", household_supply_favorite_path(@home, coffee), "我的最愛：Coffee"
    get household_supply_path(@home, coffee)
    assert_select "#favorite_supply_#{coffee.id} button[aria-pressed=false]", text: /我的最愛/

    post household_supply_favorite_path(@home, coffee), as: :turbo_stream
    assert_response :success
    assert_equal [ alex ], coffee.favorites.map(&:user)
    assert_empty soap.favorites
    %W[row_supply_#{coffee.id} card_supply_#{coffee.id} favorite_supply_#{coffee.id} starred_by_supply_#{coffee.id}
       supplies_favorites_count supplies_starred_count_all supplies_starred_count_#{alex.id}].each do |target|
      assert_match "target=\"#{target}\"", response.body
    end
    assert_select "#supplies_favorites_count:not(.hidden)", text: "1"
    post household_supply_favorite_path(@home, coffee), as: :turbo_stream
    assert_equal 1, coffee.favorites.count, "starring twice is one star"

    # Sam stars the coffee too, and the soap: three stars on two items
    [ coffee, soap ].each { it.favorites.create!(user: sam) }
    get household_supplies_path(@home, tab: "favorites")
    assert_select "li[id^=card_]", 2
    assert_select "#supplies_favorites_count:not(.hidden)", text: "2"
    assert_select "nav[aria-label=誰加的星]" do
      assert_select "a[aria-current=true]", text: /所有人/
      assert_select "#supplies_starred_count_all", "2"
      assert_select "a[href=?]", household_supplies_path(@home, tab: "favorites", by: alex.id), text: /我\s+1/
      assert_select "a[href=?]", household_supplies_path(@home, tab: "favorites", by: sam.id), text: /Sam\s+2/
    end
    assert_select "li#card_supply_#{coffee.id}" do
      assert_select "button[aria-pressed=true].bg-amber-100"
      assert_select "span.bg-teal-100[title='Sam 加的星星']", text: /S/
    end
    assert_select "li#card_supply_#{soap.id}" do
      assert_select "button[aria-pressed=false].bg-white"
      assert_select "span.bg-teal-100[title='Sam 加的星星']"
    end
    assert_select "span[title='Alex 加的星星']", 0, "your own star is the button, not a tag"

    # One person's stars
    get household_supplies_path(@home, tab: "favorites", by: sam.id)
    assert_select "li[id^=card_]", 2
    assert_select "nav[aria-label=誰加的星] a[aria-current=true].bg-teal-100", text: /Sam/
    assert_select "#supplies_favorites_count", text: "2"
    get household_supplies_path(@home, tab: "favorites", by: alex.id)
    assert_select "li[id^=card_]", 1
    assert_select "li#card_supply_#{coffee.id}"

    # All: other people's stars after the category; the item page names them
    get household_supplies_path(@home, tab: "all")
    assert_select "li#row_supply_#{soap.id} p span[title='Sam 加的星星']"
    assert_select "li#row_supply_#{plain.id} span[title]", 0
    get household_supply_path(@home, coffee)
    assert_select "#favorite_supply_#{coffee.id} input[name=_method][value=delete]"
    assert_select "#starred_by_supply_#{coffee.id} p", text: /也加了星\s*Sam/
    get household_supply_path(@home, soap)
    assert_select "#starred_by_supply_#{soap.id} p", text: /加星的人\s*Sam/

    # Taking your star away leaves Sam's: the coffee stays in Favorites. Without Turbo: back to where the star was tapped
    delete household_supply_favorite_path(@home, coffee), headers: { "HTTP_REFERER" => household_supplies_url(@home, tab: "favorites") }
    assert_redirected_to household_supplies_url(@home, tab: "favorites")
    assert_equal [ sam ], coffee.favorites.reload.map(&:user)
    get household_supplies_path(@home, tab: "favorites")
    assert_select "li[id^=card_]", 2
    assert_select "li#card_supply_#{coffee.id} button[aria-pressed=false]"
    get household_supplies_path(@home, tab: "favorites", by: alex.id)
    assert_select "li[id^=card_]", 0
    assert_select "main p", text: /你還沒有加星的品項/

    # Sam sees the same items with a teal button of their own
    sign_out
    sign_in_as sam
    coffee.favorites.create!(user: alex)
    get household_supplies_path(@home, tab: "favorites")
    assert_select "li#card_supply_#{coffee.id}" do
      assert_select "button[aria-pressed=true].bg-teal-100"
      assert_select "span.bg-amber-100[title='Alex 加的星星']", text: /A/
    end
    assert_select "nav[aria-label=誰加的星] a[href=?]", household_supplies_path(@home, tab: "favorites", by: sam.id), text: /我\s+2/
  end

  test "Favorites: a viewer sees whose stars an item has but can't star, and a viewer's old star doesn't count" do
    sam = users(:google_only)
    star = create_item(name: "Coffee", level: 30)
    plain = create_item(name: "Soap", level: 30)
    star.favorites.create!(user: users(:alex))
    plain.favorites.create!(user: sam) # from when Sam was a co-owner
    sign_out
    sign_in_as sam

    get household_supplies_path(@home, tab: "favorites")
    assert_select "li[id^=card_]", 1
    assert_select "li#card_supply_#{star.id} span.bg-amber-100[title='Alex 加的星星']", text: /A/
    assert_select "form[action=?]", household_supply_favorite_path(@home, star), 0
    assert_select "nav[aria-label=誰加的星]", 0, "one person stars here: nothing to tell apart"
    get household_supplies_path(@home, tab: "all")
    assert_select "li#row_supply_#{star.id} span[title='Alex 加的星星']"
    assert_select "li#row_supply_#{plain.id} span[title]", 0
    get household_supply_path(@home, star)
    assert_select "#starred_by_supply_#{star.id} p", text: /加星的人\s*Alex/

    post household_supply_favorite_path(@home, star), as: :turbo_stream
    assert_response :forbidden
    delete household_supply_favorite_path(@home, star), as: :turbo_stream
    assert_response :forbidden
    assert_equal [ users(:alex) ], star.favorites.reload.map(&:user)
  end

  test "To Buy, Stocked and All tabs, like Bills" do
    out = create_item(name: "Out", level: 0, guess_days_per_unit: 3)
    out.purchases.create!(household: @home, purchased_on: 10.days.ago.to_date, quantity: 1, total_price: 10, left_before: 0)
    create_item(name: "Soon", level: 3, guess_days_per_unit: 3)
    create_item(name: "Plenty", level: 50, guess_days_per_unit: 3)
    create_item(name: "Unknown", level: 5, guess_days_per_unit: nil)

    get household_supplies_path(@home)
    assert_select "nav a[aria-current=page]", /該補貨/
    get household_supplies_path(@home, tab: "all")
    soon = @home.supplies.find_by!(name: "Soon")
    assert_select "li#row_supply_#{soon.id} a.btn-press[href=?]", household_supply_path(@home, soon), text: /查看明細/
    get household_supplies_path(@home)
    # All shows its count on a phone too, like To Buy and Stocked
    assert_select "nav a[href=?] span.rounded-full:not(.max-sm\\:hidden)", household_supplies_path(@home, tab: "all"), text: @home.supplies.active.count.to_s
    assert_select "section", text: /用完或現在就補貨/ do
      assert_select "li[id^=card_]", text: /Out/
    end
    assert_select "section", text: /7 天內要補貨/ do
      assert_select "li", text: /Soon/
    end
    assert_select "li", text: /Plenty/, count: 0
    assert_select "a[href=?]", household_supplies_path(@home, tab: "stocked"), text: /下一個：Plenty/

    get household_supplies_path(@home, tab: "stocked")
    assert_select "li", text: /Plenty/
    assert_select "li", text: /移到「該補貨」/
    assert_select "section", text: /資料不足/ do
      assert_select "li", text: /Unknown/
    end
    assert_select "li", text: /Soon/, count: 0

    get household_supplies_path(@home, tab: "all")
    assert_select "main li", 4
    get household_supplies_path(@home, q: "Plen")
    assert_select "nav a[aria-current=page]", /全部/
  end

  test "All's filters are switches: several categories at once, each chip flips itself and keeps the others" do
    create_item(name: "Paper", kind: "toiletries")
    create_item(name: "Soap", kind: "cleaning")
    create_item(name: "Rice", kind: "food_drink")
    all = household_supplies_path(@home, tab: "all")

    get all
    assert_select "nav[aria-label=篩選] a", 3
    assert_select "nav[aria-label=篩選] a[aria-current]", 0
    assert_select "nav[aria-label=篩選] a", text: /準備補貨|全部|快過期/, count: 0
    assert_select "a[href=?]", household_supplies_path(@home, tab: "all", kind: [ "cleaning" ]), text: /清潔/
    assert_select "p", text: /每月約/
    assert_select "a", text: "全部清除", count: 0

    get household_supplies_path(@home, tab: "all", kind: %w[toiletries cleaning])
    assert_select "nav a[aria-current=page]", /全部/
    assert_select "main li", 2
    assert_select "main li", text: /Rice/, count: 0
    assert_select "nav[aria-label=篩選] a[aria-current=true]", 2
    assert_select "p", text: /顯示 3 項中的 2 項/
    assert_select "p", text: /每月約/, count: 0
    assert_select "a[href=?]", all, text: "全部清除"
    # a chosen chip leads to the list without it; another one is added to the chosen ones
    assert_select "a[aria-current=true][href=?]", household_supplies_path(@home, tab: "all", kind: [ "toiletries" ]), text: /清潔/
    assert_select "a[href=?]", household_supplies_path(@home, tab: "all", kind: %w[toiletries cleaning food_drink])
    # the search keeps the chosen filters
    assert_select "form input[type=hidden][name='kind[]']", 2

    # one category, as older links give it
    get household_supplies_path(@home, kind: "food_drink")
    assert_select "main li", 1
    assert_select "main li", text: /Rice/
  end

  test "All's Expiring filter shows only while something is expiring, and narrows the chosen categories" do
    create_item(name: "Paper", kind: "toiletries")
    get household_supplies_path(@home, tab: "all")
    assert_select "nav[aria-label=篩選] a", text: /快過期/, count: 0

    milk = create_item(name: "Milk", kind: "food_drink", level: 30, guess_days_per_unit: 30)
    milk.purchases.create!(household: @home, purchased_on: @home.today, quantity: 30, total_price: 300, left_before: 0, expires_on: @home.today + 5)
    create_item(name: "Rice", kind: "food_drink")
    get household_supplies_path(@home, tab: "all")
    assert_select "nav[aria-label=篩選] a", text: /快過期\s*1/

    get household_supplies_path(@home, tab: "all", filter: "expiring", kind: %w[food_drink toiletries])
    assert_select "main li", 1
    assert_select "main li", text: /Milk/
    assert_select "p", text: /顯示 3 項中的 1 項/
    assert_select "a[aria-current=true][href=?]", household_supplies_path(@home, tab: "all", kind: %w[toiletries food_drink]), text: /快過期/
  end

  test "the old Buy soon filter opens To Buy, where those items are" do
    create_item(name: "Soon", level: 1)
    get household_supplies_path(@home, filter: "buy_soon")
    assert_select "nav a[aria-current=page]", /該補貨/
    assert_select "main li", text: /Soon/
  end

  test "a viewer sees supplies but can't change them" do
    supply = create_item
    sign_in_as users(:google_only)
    get household_supplies_path(@home)
    assert_response :success
    assert_select "a[href=?]", new_household_supply_purchase_path(@home, supply), 0
    get household_supply_path(@home, supply)
    assert_response :success
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }
    assert_response :forbidden
    post household_supplies_path(@home), params: { supply: { name: "X", kind: "other", unit: "piece", level: 1 } }
    assert_response :forbidden
    get new_household_supply_purchase_path(@home, supply)
    assert_response :forbidden
    get scan_household_supplies_path(@home)
    assert_response :forbidden
    get scan_household_supplies_path(@home, mode: "pdf")
    assert_response :forbidden
    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: { "0" => { name: "a.pdf", words: file_fixture("einvoice/invoice_pdf_words.json").read } } }
    assert_response :forbidden
  end

  test "an old price: listed in Price history and Where to buy, with no change to the count or forecast" do
    supply = create_item(level: 0)
    supply.purchases.create!(household: @home, purchased_on: @home.today - 3, quantity: 12, total_price: 289, store: "Costco", left_before: 0)
    supply.update!(level: 0)
    forecast_before = supply.reload.forecast.status

    get household_supply_path(@home, supply)
    assert_select "details##{ActionView::RecordIdentifier.dom_id(supply, :price_history)}" do
      assert_select "summary", /價格記錄/
      assert_select "a[href=?]", new_household_supply_price_path(@home, supply), /新增舊價格/
    end

    get new_household_supply_price_path(@home, supply)
    assert_select "input[name='supply_price[product_name]'][value=?]", "Toilet paper"
    assert_select "input[name='supply_price[store]'][value=?]", "Costco"

    assert_no_difference -> { supply.counts.count } do
      assert_no_difference -> { @home.records.count } do
        post household_supply_prices_path(@home, supply), params: { supply_price: { product_name: "Kleenex 3-ply 6 rolls", store: "PX Mart", quantity: 6, total_price: 119, purchased_on: @home.today - 100 } }
      end
    end
    assert_redirected_to household_supply_path(@home, supply)
    price = supply.prices.sole
    assert_equal "Kleenex 3-ply 6 rolls", price.display_name
    supply.reload
    assert_equal 0, supply.level
    assert_equal 1, supply.purchases.count
    assert_equal forecast_before, supply.forecast.status

    # Same name as the item: stored blank, shown as the item's name
    post household_supply_prices_path(@home, supply), params: { supply_price: { product_name: "Toilet paper", store: "Carrefour", quantity: 6, total_price: 60, purchased_on: @home.today - 200 } }
    assert_nil supply.prices.find_by(store: "Carrefour").product_name

    get household_supply_path(@home, supply)
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :price_history)} ul li", 3
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :price_history)} ul li:first-child", /Toilet paper.*Costco/m
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :price_history)} ul li", text: /舊價格/, count: 2
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :price_history)} ul li:last-child", /最低/
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :price_history)} table tbody tr", 3
    assert_match "最低每捲 NT$10", response.body
    # Where to buy counts the old price: Carrefour (NT$10/roll) beats Costco (NT$24.1/roll)
    assert_match "Carrefour 最便宜：每捲 NT$10", response.body
    # Total spent is still the real purchase only
    assert_match "NT$289", response.body.match(/總花費：[^<]*/).to_s

    delete household_supply_price_path(@home, supply, price)
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal 1, supply.prices.count
  end

  test "an old price can't be in the future, and a viewer can't add or delete one" do
    supply = create_item
    post household_supply_prices_path(@home, supply), params: { supply_price: { store: "Costco", quantity: 6, total_price: 99, purchased_on: @home.today + 1 } }
    assert_response :unprocessable_content
    assert_equal 0, supply.prices.count
    price = supply.prices.create!(household: @home, quantity: 6, total_price: 99, purchased_on: @home.today)

    sign_in_as users(:google_only)
    get household_supply_path(@home, supply)
    assert_select "a[href=?]", new_household_supply_price_path(@home, supply), 0
    get new_household_supply_price_path(@home, supply)
    assert_response :forbidden
    post household_supply_prices_path(@home, supply), params: { supply_price: { quantity: 6, total_price: 99, purchased_on: @home.today } }
    assert_response :forbidden
    delete household_supply_price_path(@home, supply, price)
    assert_response :forbidden
    assert_equal 1, supply.prices.count
  end

  test "dialog on a computer: Bought more loads into the modal frame with a dialog" do
    supply = create_item
    get new_household_supply_purchase_path(@home, supply), headers: { "Turbo-Frame" => "modal" }
    assert_select "turbo-frame#modal dialog[data-controller=modal] form[data-turbo-frame=_top]"
    get new_household_supply_purchase_path(@home, supply)
    assert_select "dialog[data-controller=modal]", 0
    assert_select "h1", /已補貨/
  end

  test "Log a purchase: buy-soon items first, then the rest" do
    create_item(name: "Plenty", level: 50)
    create_item(name: "Soon", level: 1)
    get restock_household_supplies_path(@home)
    assert_select "section:first-of-type h3", /準備補貨/
    assert_select "section:first-of-type li", text: /Soon/
  end

  test "scan a barcode: known item → its Bought form; found → New item filled in; unknown → empty with the barcode" do
    supply = create_item
    supply.barcodes.create!(household: @home, code: "4710000000017")
    get scan_barcode_household_supplies_path(@home, code: "4710000000017")
    assert_redirected_to new_household_supply_purchase_path(@home, supply, scan: 1, barcode: "4710000000017")

    ProductLookup.create!(code: "7394376616228", source: "open_food_facts", name: "燕麥奶", kind_guess: "food_drink", fetched_at: Time.current)
    get scan_barcode_household_supplies_path(@home, code: "7394376616228")
    follow_redirect!
    assert_select "input[name='supply[name]'][value=燕麥奶].bg-green-50"
    assert_select "input[type=hidden][name=barcode][value=7394376616228]"

    post household_supplies_path(@home), params: { barcode: "7394376616228", log_purchase: "1", purchase: { total_price: 120, store: "全聯" },
                                                   supply: { name: "燕麥奶", kind: "food_drink", unit: "bottle", level: 2 } }
    milk = @home.supplies.find_by!(name: "燕麥奶")
    assert_equal [ "7394376616228" ], milk.barcodes.map(&:code)
    assert_equal [ [ 2, 120, "全聯" ] ], milk.purchases.map { [ it.quantity, it.total_price, it.store ] }

    ProductLookup.create!(code: "4710000000024", fetched_at: Time.current)
    get scan_barcode_household_supplies_path(@home, code: "4710000000024")
    follow_redirect!
    assert_select "dialog[data-controller=notice][data-notice-focus-value='#supply_name']" do
      assert_select "h2", "找不到這個商品"
      assert_select "p", /請自己輸入名稱、類別和單位/
    end
    assert_select "input[type=hidden][name=not_found][value='1']"
  end

  test "another brand joins an item: scan → It's one of my items → pick → Restocked remembers the barcode and the product" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 1)
    shampoo.purchases.create!(household: @home, purchased_on: @home.today - 30, quantity: 2, total_price: 289, store: "Coupang", left_before: 0, product_name: "Pantene 700ml")
    ProductLookup.create!(code: "4710000000031", source: "open_beauty_facts", name: "Lux Shampoo 750ml", kind_guess: "toiletries", fetched_at: Time.current)

    get scan_barcode_household_supplies_path(@home, code: "4710000000031")
    follow_redirect!
    pick = restock_household_supplies_path(@home, barcode: "4710000000031", product_name: "Lux Shampoo 750ml")
    assert_select "a[href=?]", pick, text: /這是我已有的項目/
    assert_select "input[type=hidden][name=product_name][value='Lux Shampoo 750ml']"

    get pick
    assert_select "h1", /這是哪個項目/
    assert_select "p", /條碼 4710000000031（Lux Shampoo 750ml）會記在你選的項目上/
    form = new_household_supply_purchase_path(@home, shampoo, barcode: "4710000000031", product_name: "Lux Shampoo 750ml")
    assert_select "a[href=?]", form, text: /Shampoo/

    get form
    assert_select "p", /儲存後，條碼 4710000000031 會記在「Shampoo」上/
    assert_select "input[name='supply_purchase[product_name]'][value='Lux Shampoo 750ml'].bg-green-50"
    assert_select "input[name='supply_purchase[total_price]']:not([value])", 1, "a brand bought for the first time: not Pantene's price"
    assert_select "input[name='supply_purchase[store]'][value=Coupang]"
    assert_select "datalist#supply-products option[value='Pantene 700ml']"
    assert_select "input[type=hidden][name=barcode][value='4710000000031']"

    assert_no_difference -> { @home.supplies.count } do
      post household_supply_purchases_path(@home, shampoo), params: { barcode: "4710000000031",
        supply_purchase: { product_name: "Lux Shampoo 750ml", quantity: 2, total_price: 398, store: "PX Mart", purchased_on: @home.today, left_before: 1 } }
    end
    assert_redirected_to household_supply_path(@home, shampoo)
    assert_equal 3, shampoo.reload.level, "every brand counts together"
    assert_equal [ [ "4710000000031", "Lux Shampoo 750ml" ] ], shampoo.barcodes.map { [ it.code, it.product_name ] }
    assert_equal [ "Pantene 700ml", "Lux Shampoo 750ml" ], shampoo.purchases.order(:purchased_on).map(&:product_name)

    # the item's page names each brand; the lists name the one bought last and the search finds it
    follow_redirect!
    assert_select "li", /PX Mart.*Lux Shampoo 750ml/m
    assert_select "td span", "Pantene 700ml"
    assert_select "li", /\+2 瓶.*PX Mart.*Lux Shampoo 750ml/m
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} p span", "Lux Shampoo 750ml"
    get household_supplies_path(@home, q: "pantene")
    assert_select "main li", 1
    assert_select "#row_supply_#{shampoo.id}"

    # the next scan of that bottle goes straight to the item, with the product filled in
    get scan_barcode_household_supplies_path(@home, code: "4710000000031")
    assert_redirected_to new_household_supply_purchase_path(@home, shampoo, scan: 1, barcode: "4710000000031")
    follow_redirect!
    assert_select "input[name='supply_purchase[product_name]'][value='Lux Shampoo 750ml']"
    assert_select "input[name='supply_purchase[total_price]'][value='398']", 1, "this product's last price"
    assert_select "p", text: /會記在「Shampoo」上/, count: 0
  end

  test "a purchase's product: empty or the item's own name is no product, and over 80 characters is refused" do
    supply = create_item(name: "Shampoo", unit: "bottle")
    post household_supply_purchases_path(@home, supply), params: { supply_purchase: { product_name: " Shampoo ", quantity: 1, total_price: 100, purchased_on: @home.today, left_before: 4 } }
    assert_nil supply.purchases.sole.product_name
    assert_equal "Shampoo", supply.purchases.sole.display_name
    post household_supply_purchases_path(@home, supply), params: { supply_purchase: { product_name: "x" * 81, quantity: 1, total_price: 100, purchased_on: @home.today, left_before: 5 } }
    assert_response :unprocessable_content
    assert_equal 1, supply.purchases.count

    # Edit corrects the last purchase's product
    patch household_supply_path(@home, supply), params: { supply: { name: "Shampoo" }, purchase: { product_name: "Lux 750ml", quantity: 1, total_price: 100, purchased_on: @home.today } }
    assert_equal "Lux 750ml", supply.purchases.sole.product_name
  end

  test "Edit lists the item's barcodes; Remove unlinks one, a viewer can't, and an archived item's barcode moves to the item picked" do
    shampoo = create_item(name: "Shampoo", unit: "bottle")
    barcode = shampoo.barcodes.create!(household: @home, code: "4710000000031", product_name: "Lux Shampoo 750ml")
    get edit_household_supply_path(@home, shampoo)
    assert_select "section[aria-labelledby=supply-barcodes] li", /Lux Shampoo 750ml.*4710000000031/m
    assert_select "form[action=?] button[aria-label='移除條碼 4710000000031']", household_supply_barcode_path(@home, shampoo, barcode)

    sign_in_as users(:google_only)
    delete household_supply_barcode_path(@home, shampoo, barcode)
    assert_response :forbidden
    post household_supply_purchases_path(@home, shampoo), params: { barcode: "4710000000048", supply_purchase: { quantity: 1, total_price: 100, purchased_on: @home.today, left_before: 4 } }
    assert_response :forbidden
    assert_equal 1, shampoo.barcodes.count

    sign_in_as users(:alex)
    delete household_supply_barcode_path(@home, shampoo, barcode)
    assert_redirected_to household_supply_path(@home, shampoo)
    assert_empty shampoo.barcodes.reload

    # a duplicate item put away: its barcode goes to the item it is bought as next
    duplicate = create_item(name: "Lux Shampoo 750ml", unit: "bottle", archived_at: Time.current)
    duplicate.barcodes.create!(household: @home, code: "4710000000031")
    get scan_barcode_household_supplies_path(@home, code: "4710000000031")
    follow_redirect!
    assert_select "a", text: /這是我已有的項目/
    post household_supply_purchases_path(@home, shampoo), params: { barcode: "4710000000031",
      supply_purchase: { product_name: "Lux Shampoo 750ml", quantity: 1, total_price: 199, purchased_on: @home.today, left_before: 4 } }
    assert_equal shampoo, @home.supply_barcodes.find_by!(code: "4710000000031").supply

    # a barcode another item in use has stays there
    other = create_item(name: "Soap")
    other.barcodes.create!(household: @home, code: "4710000000048")
    post household_supply_purchases_path(@home, shampoo), params: { barcode: "4710000000048", supply_purchase: { quantity: 1, total_price: 100, purchased_on: @home.today, left_before: 5 } }
    assert_equal other, @home.supply_barcodes.find_by!(code: "4710000000048").supply
  end

  test "a Taiwan e-invoice: review, save once with one Ledger expense, remembered next time, refused twice" do
    supply = create_item(name: "衛生紙")
    head = "AB12345678" "1151115" "1234" "0000010E" "0000011B" "00000000" "12345678" + ("x" * 24)
    left = "#{head}:**********:3:3:1:舒潔衛生紙:1:189:鮮奶:2:47:運費:1:60"

    post receipt_review_household_supplies_path(@home), params: { source: "qr", left:, right: "" }
    assert_response :success
    assert_select "select[name='invoices[0][lines][0][choice]'] optgroup[label=盥洗用品] option[selected][value=?]", supply.id.to_s
    assert_select "select[name='invoices[0][lines][0][choice]'] optgroup", 2, "one category in use, then Add as new / Skip"
    assert_select "select[name='invoices[0][lines][0][choice]'] optgroup option[value=new]"
    assert_select "span", text: "建議"
    assert_select "dialog[data-controller=notice] h2", "1 項找不到", "鮮奶 matches nothing"
    assert_select "details[open] input[name='invoices[0][lines][1][name]'][value=鮮奶]"
    assert_select "span", text: "找不到"
    assert_select "select[name='invoices[0][lines][2][choice]'] option[selected][value=skip]", 1, "shipping starts skipped"
    assert_select "span", text: "運費等 · 略過"
    assert_select "input[name='invoices[0][lines][1][quantity]'][value='2']"

    assert_difference -> { @home.records.count } => 1, -> { @home.supply_purchases.count } => 2 do
      post receipt_household_supplies_path(@home), params: { source: "qr", left:, add_to_ledger: "1",
        invoices: { "0" => { store: "全聯", lines: { "0" => { choice: supply.id, quantity: 1, units_per_line: 12 },
                                                    "1" => { choice: "new", quantity: 3, name: "鮮奶", kind: "food_drink", unit: "bottle", units_per_line: 1 },
                                                    "2" => { choice: "skip" } } } } }
    end
    assert_redirected_to household_supplies_path(@home)
    assert_match "已從1 張發票儲存 2 筆購買，並在帳本記了 1 筆支出", flash[:notice]
    assert_equal 283, @home.records.order(:id).last.amount_paid
    assert_equal 4 + 12, supply.reload.level
    assert_equal "舒潔衛生紙", supply.purchases.sole.product_name, "the receipt line's text is the product bought"
    assert_equal 3, @home.supplies.find_by!(name: "鮮奶").level, "the quantity typed on the review wins"
    assert_equal "全聯", @home.receipt_sellers.sole.name

    post receipt_review_household_supplies_path(@home), params: { source: "qr", left: }
    assert_redirected_to scan_household_supplies_path(@home, mode: "receipt")
    assert_match "已經在", flash[:alert]

    other = left.sub("AB12345678", "AB12345679")
    post receipt_review_household_supplies_path(@home), params: { source: "qr", left: other }
    assert_select "span", text: "已記住"
    assert_select "dialog[data-controller=notice]", 0, "every line is remembered"
    assert_select "input[name='invoices[0][store]'][value=全聯]"
    assert_select "input[name='invoices[0][lines][0][units_per_line]'][value='12']"

    post receipt_review_household_supplies_path(@home), params: { source: "qr", left: "https://example.com" }
    assert_match "不像台灣電子發票", flash[:alert]
  end

  test "invoice PDFs: items listed by invoice, the rest under Not included; exclude, not a supplies store, total only" do
    cleaner = create_item(name: "馬桶清潔劑")
    words = file_fixture("einvoice/invoice_pdf_words.json").read
    unreadable = [ { s: "Hello", x: 10, y: 10, w: 20, h: 9 } ].to_json
    # Another store's PDF: no item list, only a total
    total_only = [ { s: "12345679 某某商店", x: 40, y: 80, w: 90, h: 10 }, { s: "AB98765432", x: 40, y: 120, w: 50, h: 9 },
                   { s: "2026/11/08", x: 120, y: 120, w: 47, h: 9 }, { s: "總計", x: 40, y: 160, w: 18, h: 9 }, { s: "812", x: 100, y: 160, w: 15, h: 9 } ].to_json
    pdfs = { "0" => { name: "發票明細_HX45765353.pdf", words: }, "1" => { name: "copy.pdf", words: },
             "2" => { name: "scan_0001.pdf", words: unreadable }, "3" => { name: "invoice_1108.pdf", words: total_only } }

    get scan_household_supplies_path(@home, mode: "pdf")
    assert_select "[data-controller=receipt-pdf] input[type=file][multiple]"
    assert_select "a[aria-current=page][href=?]", scan_household_supplies_path(@home, mode: "pdf")

    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: }
    assert_response :success
    assert_select "section#invoice_0" do
      assert_select "input[name='invoices[0][store]'][value=徠樂企業社]"
      assert_select "li", 2
      assert_select "select[name='invoices[0][lines][0][choice]'] option[selected][value=?]", cleaner.id.to_s
      assert_select "select[name='invoices[0][lines][1][choice]'] option[selected][value=skip]"
      assert_select "input[name='invoices[0][lines][0][quantity]'][value='2']"
    end
    assert_select "h2#not_included_title", "沒有加入（3）"
    assert_match "跟上面是同一張", response.body
    assert_match "無法讀取", response.body
    assert_match "這個 PDF 裡沒有品項", response.body
    assert_select "input[type=hidden][name='pdfs[0][words]']"

    assert_difference -> { @home.supply_purchases.count } => 1, -> { @home.records.count } => 1 do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
        invoices: { "0" => { store: "徠樂", lines: { "0" => { choice: cleaner.id, quantity: 2, units_per_line: 1 }, "1" => { choice: "skip" } } },
                    "3" => { ledger_total: "1", store: "某某商店" } } }
    end
    assert_equal [ [ 2, 120, "徠樂" ] ], cleaner.purchases.map { [ it.quantity, it.total_price.to_i, it.store ] }
    assert_equal 812, @home.records.order(:id).last.amount_paid
    assert_match "已從2 張發票儲存 1 筆購買", flash[:notice]

    # Added before now; excluding another as "not a supplies store" puts its next receipts under Not included
    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: }
    assert_match "已在", response.body
    restaurant = [ { s: "22222222 某某餐廳", x: 40, y: 80, w: 90, h: 10 }, { s: "CD11112222", x: 40, y: 120, w: 50, h: 9 },
                   { s: "2026/11/05", x: 120, y: 120, w: 47, h: 9 }, { s: "品名", x: 40, y: 150, w: 18, h: 9 }, { s: "數量", x: 200, y: 150, w: 18, h: 9 },
                   { s: "金額", x: 260, y: 150, w: 18, h: 9 }, { s: "牛肉麵", x: 40, y: 170, w: 30, h: 9 }, { s: "1", x: 206, y: 170, w: 5, h: 9 },
                   { s: "320", x: 262, y: 170, w: 15, h: 9 }, { s: "總計", x: 40, y: 200, w: 18, h: 9 }, { s: "320", x: 262, y: 200, w: 15, h: 9 } ].to_json
    meal = { "0" => { name: "receipt_1105.pdf", words: restaurant } }
    assert_no_difference -> { @home.supply_purchases.count } do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs: meal,
        invoices: { "0" => { exclude: "1", skip_store: "1", store: "某某餐廳", lines: { "0" => { choice: "new", name: "牛肉麵" } } } } }
    end
    assert_match "沒有加入任何東西", flash[:notice]
    assert @home.receipt_sellers.find_by!(tax_id: "22222222").skip
    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: meal }
    assert_select "section[id^=invoice_]", 1, "only inside the folded Not included row"
    assert_match "不是日用品店", response.body
    assert_select "input[name='invoices[0][include]']"
  end

  test "a new item bought a while ago with some used: the forecast has a usage rate straight away" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon # a purchase on a past day counts from its midday
    bought_on = @home.today - 10
    post household_supplies_path(@home), params: { supply: { name: "Toilet paper", kind: "toiletries", unit: "roll", level: 5 },
                                                   purchase: { purchased_on: bought_on, quantity: 12, total_price: 289, store: "Costco" } }
    supply = @home.supplies.sole
    assert_equal [ [ bought_on, 12, 0 ] ], supply.purchases.map { [ it.purchased_on, it.quantity, it.left_before ] }
    assert_equal 5, supply.reload.level
    forecast = supply.forecast
    assert forecast.enough_data?, "7 used in 10 days"
    assert_in_delta 0.7, forecast.rate, 0.05
    assert_equal @home.today + 7, forecast.run_out_on

    get household_supply_path(@home, supply)
    assert_select "section", /Uses about 5 rolls a week|大約每週 5 捲/
  end

  test "bought today with none used: just the purchase; a future date is refused" do
    post household_supplies_path(@home), params: { supply: { name: "Soap", kind: "cleaning", unit: "bottle", level: 3 },
                                                   purchase: { quantity: 3, total_price: 150 } }
    supply = @home.supplies.sole
    assert_equal [ 3 ], supply.purchases.map(&:quantity)
    assert_empty supply.counts

    post household_supplies_path(@home), params: { supply: { name: "Rice", kind: "food_drink", unit: "bag", level: 1 },
                                                   purchase: { purchased_on: @home.today + 1, quantity: 1, total_price: 300 } }
    assert_response :unprocessable_content
    assert_select "li", /不能是未來的日期/
    assert_nil @home.supplies.find_by(name: "Rice")
  end

  test "edit: the latest purchase's price and store can be corrected, and its Ledger expense follows" do
    supply = create_item
    purchase = Supplies::LogPurchase.call(supply, { quantity: 12, total_price: 289, store: "Costco", purchased_on: @home.today }, user: users(:alex), add_to_ledger: true)
    get edit_household_supply_path(@home, supply)
    assert_select "details[open] input[name='purchase[total_price]'][value='289']"

    patch household_supply_path(@home, supply), params: { supply: { name: supply.name },
      purchase: { purchased_on: @home.today, quantity: 12, total_price: 259, store: "家樂福" } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 259, "家樂福" ], purchase.reload.values_at(:total_price, :store)
    assert_equal 259, purchase.record.reload.amount_paid
    assert_equal 1, supply.purchases.count
  end

  test "edit: an item added without a purchase can get one afterwards, before its first count" do
    post household_supplies_path(@home), params: { supply: { name: "Shampoo", kind: "toiletries", unit: "bottle", level: 2 } }
    supply = @home.supplies.sole
    patch household_supply_path(@home, supply), params: { supply: { name: "Shampoo" },
      purchase: { purchased_on: @home.today - 20, quantity: 3, total_price: 597, store: "屈臣氏" } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 0 ], supply.purchases.map(&:left_before)
    assert_equal 2, supply.reload.level, "the count after it still says how many are left"
    assert supply.forecast.enough_data?, "1 used in 20 days"

    patch household_supply_path(@home, supply), params: { supply: { name: "Shampoo" }, purchase: { purchased_on: @home.today, quantity: 3, total_price: "1.5" } }
    assert_response :unprocessable_content
    assert_equal 597, supply.purchases.sole.reload.total_price
  end
end
