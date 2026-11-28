require "test_helper"

class SuppliesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    sign_in_as users(:alex)
  end

  # One of the six categories every ledger starts with, by its key
  def category(key) = SupplyCategory.for_key(@home, key)

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

    post household_supplies_path(@home), params: { supply: { name: "Toilet paper", supply_category_id: category("toiletries").id, unit: "roll", level: 4, guess_days_per_unit: 3, lead_days: 3, alert_when_left: 0 } }
    supply = @home.supplies.sole
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal "toiletries", supply.category.key
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
    assert_select "span.whitespace-nowrap", "NT$289 買 12"
    assert_select "span.whitespace-nowrap", "每捲 NT$24.1"
    get household_supplies_path(@home, tab: "all")
    assert_select "li##{ActionView::RecordIdentifier.dom_id(supply, :row)}", /Toilet paper/
    # No add button of its own (like Bills): the header's New is the one place to add
    assert_select "main details summary", text: /新增日用品/, count: 0
    assert_select "header a[href=?]", new_household_supply_path(@home)
    assert_select "header a[href=?]", scan_household_supplies_path(@home)
  end

  test "the take-one-off button and the hints name the item's own unit, on cards, All rows and the item's page" do
    paper = create_item(guess_days_per_unit: nil)
    soap = create_item(name: "Dish soap", unit: "pack", guess_days_per_unit: 30)
    # The cards are on To Buy and Favorites
    [ paper, soap ].each { it.favorites.create!(user: users(:alex)) }
    get household_supplies_path(@home, tab: "favorites")
    assert_select "#card_supply_#{paper.id} button[aria-label='Toilet paper 用掉 1 捲']", "用掉 1 捲"
    assert_select "#card_supply_#{soap.id} button[aria-label='Dish soap 用掉 1 包']", "用掉 1 包"
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{paper.id} button", "用掉 1 捲"
    assert_select "#row_supply_#{paper.id} p", "資料不足 · 按「用掉 1 捲」或更新數量"
    assert_select "#row_supply_#{soap.id} button", "用掉 1 包"
    get household_supply_path(@home, soap)
    assert_select "button[aria-label='Dish soap 用掉 1 包']", "用掉 1 包"
    assert_select "li", "開始使用新的日用品時按「用掉 1 包」，或定期更新一下數量。"

    users(:alex).update!(locale: "en")
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{paper.id} button[aria-label='Used 1 roll: Toilet paper']", "Used 1 roll"
    assert_select "#row_supply_#{paper.id} p", 'Not enough data yet · tap "Used 1 roll" or update the count'
    assert_select "#row_supply_#{soap.id} button", "Used 1 pack"
  end

  test "−1 at 0 stays at 0, and the button is off" do
    supply = create_item(level: 0)
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    assert_equal 0, supply.reload.level
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉 1 捲']"
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
    assert_match(/<button[^>]*disabled[^>]*aria-label="Toilet paper 用掉 1 捲"/, response.body)

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
    assert_select "button[disabled][aria-label*='用掉 1 捲']"
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: 1 } }, as: :turbo_stream
    assert_no_match "dialog data-controller", response.body
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉 1 捲']", 0
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
    post household_supplies_path(@home), params: { supply: { name: "Soap", supply_category_id: category("cleaning").id, unit: "bottle", level: -2 } }
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

    item.favorites.create!(user: users(:alex))
    get household_supplies_path(@home, tab: "favorites")
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

    # The star is on the All rows and the item page (and on the cards, further down)
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

  test "To Buy, Favorites and All tabs, like Bills; All is every item and replaced Stocked" do
    out = create_item(name: "Out", level: 0, guess_days_per_unit: 3)
    out.purchases.create!(household: @home, purchased_on: 10.days.ago.to_date, quantity: 1, total_price: 10, left_before: 0)
    create_item(name: "Soon", level: 3, guess_days_per_unit: 3)
    create_item(name: "Plenty", level: 50, guess_days_per_unit: 3)
    create_item(name: "Unknown", level: 5, guess_days_per_unit: nil)

    # Supplies opens on All
    get household_supplies_path(@home)
    assert_select "nav a[aria-current=page]", /全部/
    soon = @home.supplies.find_by!(name: "Soon")
    assert_select "li#row_supply_#{soon.id} a.btn-press[href=?]", household_supply_path(@home, soon), text: /查看明細/
    assert_select "nav a[href=?]", household_supplies_path(@home, tab: "to_buy"), text: /該補貨/
    # Three tabs: no Stocked
    assert_select "nav[aria-label=日用品檢視] a", 3
    assert_select "nav[aria-label=日用品檢視] a", text: /還夠用/, count: 0
    get household_supplies_path(@home, tab: "to_buy")
    assert_select "nav a[aria-current=page]", /該補貨/
    # All shows its count on a phone too, like To Buy
    assert_select "nav a[href=?] span.rounded-full:not(.max-sm\\:hidden)", household_supplies_path(@home, tab: "all"), text: @home.supplies.active.count.to_s
    assert_select "section", text: /用完或現在就補貨/ do
      assert_select "li[id^=card_]", text: /Out/
    end
    assert_select "section", text: /7 天內要補貨/ do
      assert_select "li", text: /Soon/
    end
    assert_select "li", text: /Plenty/, count: 0
    # Next up opens All
    assert_select "main a[href=?]", household_supplies_path(@home, tab: "all"), text: /下一個：Plenty.*全部/m

    # All: every item once. Only the one with enough for now says when it moves to To Buy
    get household_supplies_path(@home, tab: "all")
    assert_select "main li", 4
    plenty, unknown = %w[Plenty Unknown].map { @home.supplies.find_by!(name: it) }
    assert_select "li#row_supply_#{plenty.id} p", text: /移到「該補貨」/
    assert_select "main li p", text: /移到「該補貨」/, count: 1
    assert_select "li#row_supply_#{unknown.id} span", text: "資料不足"

    # An old link to Stocked opens All
    get household_supplies_path(@home, tab: "stocked")
    assert_response :success
    assert_select "nav a[aria-current=page]", /全部/
    assert_select "main li[id^=row_]", 4
    get household_supplies_path(@home, q: "Plen")
    assert_select "nav a[aria-current=page]", /全部/
  end

  test "the item running out first comes first; without a run-out date, the fewest left" do
    create_item(name: "Later", level: 50, guess_days_per_unit: 3)
    create_item(name: "Sooner", level: 3, guess_days_per_unit: 3)
    { "Apple" => 4, "Banana" => 1, "Cherry" => 3, "Date" => 0, "Elder" => 1 }.each { |name, level| create_item(name:, level:, guess_days_per_unit: nil) }

    # Dated items by date, then the ones without data by what is left (ties A to Z), not A to Z
    get household_supplies_path(@home)
    assert_equal %w[Sooner Later Date Banana Elder Cherry Apple], css_select("main li[id^=row_] div.min-w-0 > a").map(&:text)
  end

  test "All's filters are switches: several categories at once, each chip flips itself and keeps the others" do
    create_item(name: "Paper", kind: "toiletries")
    create_item(name: "Soap", kind: "cleaning")
    create_item(name: "Rice", kind: "food_drink")
    all = household_supplies_path(@home, tab: "all")
    toiletries, cleaning, food = %w[toiletries cleaning food_drink].map { category(it).id }

    get all
    assert_select "nav[aria-label=篩選] a.rounded-full", 3
    assert_select "nav[aria-label=篩選] a[aria-current]", 0
    assert_select "nav[aria-label=篩選] a", text: /準備補貨|全部|快過期/, count: 0
    assert_select "a[href=?]", household_supplies_path(@home, tab: "all", category: [ cleaning ]), text: /清潔/
    # Edit categories is a button under the chips, not one of the filters
    assert_select "nav[aria-label=篩選] a[href=?]", household_categories_path(@home, anchor: "supplies"), count: 0
    assert_select "nav[aria-label=篩選] + div a.btn-press[href=?]", household_categories_path(@home, anchor: "supplies"), text: "編輯類別"
    assert_select "p", text: /每月約/
    assert_select "a", text: "全部清除", count: 0

    get household_supplies_path(@home, tab: "all", category: [ cleaning, toiletries ])
    assert_select "nav a[aria-current=page]", /全部/
    assert_select "main li", 2
    assert_select "main li", text: /Rice/, count: 0
    assert_select "nav[aria-label=篩選] a[aria-current=true]", 2
    assert_select "p", text: /顯示 3 項中的 2 項/
    assert_select "p", text: /每月約/, count: 0
    assert_select "a[href=?]", all, text: "全部清除"
    # a chosen chip leads to the list without it; another one is added to the chosen ones
    assert_select "a[aria-current=true][href=?]", household_supplies_path(@home, tab: "all", category: [ toiletries ]), text: /清潔/
    assert_select "a[href=?]", household_supplies_path(@home, tab: "all", category: [ toiletries, cleaning, food ])
    # the search keeps the chosen filters
    assert_select "form input[type=hidden][name='category[]']", 2

    # one category on its own; one that isn't the ledger's is ignored
    get household_supplies_path(@home, category: food)
    assert_select "main li", 1
    assert_select "main li", text: /Rice/
    get household_supplies_path(@home, tab: "all", category: [ SupplyCategory.for_key(households(:parents), "food_drink").id ])
    assert_select "main li", 3

    # a category of the ledger's own is a filter like the starting six, in the list's order
    shampoo = SupplyCategory.named(@home, "洗髮精")
    create_item(name: "Lux", category: shampoo)
    get all
    assert_select "nav[aria-label=篩選] a.rounded-full", 4
    assert_select "nav[aria-label=篩選] a.rounded-full:last-of-type", text: /洗髮精/
    get household_supplies_path(@home, tab: "all", category: [ shampoo.id ])
    assert_select "main li", 1
    assert_select "main li", text: /Lux.*洗髮精/m

    # a viewer filters too, but gets no link to edit the categories
    sign_in_as users(:google_only)
    get all
    assert_select "nav[aria-label=篩選] a.rounded-full", 4
    assert_select "a", text: "編輯類別", count: 0
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

    get household_supplies_path(@home, tab: "all", filter: "expiring", category: [ category("food_drink").id, category("toiletries").id ])
    assert_select "main li", 1
    assert_select "main li", text: /Milk/
    assert_select "p", text: /顯示 3 項中的 1 項/
    assert_select "a[aria-current=true][href=?]", household_supplies_path(@home, tab: "all", category: [ category("toiletries").id, category("food_drink").id ]), text: /快過期/
  end

  test "the old Buy soon filter opens To Buy, where those items are" do
    create_item(name: "Soon", level: 1)
    get household_supplies_path(@home, filter: "buy_soon")
    assert_select "nav a[aria-current=page]", /該補貨/
    assert_select "main li", text: /Soon/
  end

  test "History reads a −1 as Used 1 with what's left, and a typed count as Counted" do
    supply = create_item
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: 2 } }, as: :turbo_stream
    assert_equal [ true, false ], supply.counts.order(:id).map(&:used_one)

    get household_supply_path(@home, supply)
    assert_select "#history_supply_#{supply.id} ul li", text: /用掉 1 · 剩 3 捲/, count: 1
    assert_select "#history_supply_#{supply.id} ul li", text: /數量：2 捲/, count: 1
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
    post household_supplies_path(@home), params: { supply: { name: "X", supply_category_id: category("other").id, unit: "piece", level: 1 } }
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
    assert_select "h1", /補貨：/
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
                                                   supply: { name: "燕麥奶", supply_category_id: category("food_drink").id, unit: "bottle", level: 2 } }
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

    # the item's page names each brand; an All row's Last bought is the store and price alone, and the search still finds a brand
    follow_redirect!
    assert_select "li", /PX Mart.*Lux Shampoo 750ml/m
    assert_select "td span", "Pantene 700ml"
    assert_select "li", /\+2 瓶.*PX Mart.*Lux Shampoo 750ml/m
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} > p", /\APX Mart\u00A0· /
    assert_select "#row_supply_#{shampoo.id} > p", text: /Lux Shampoo 750ml/, count: 0
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

  # Shampoo with 1 Pantene (bought a month ago) and 2 Lux (bought today)
  def two_brands
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 145, store: "Coupang", purchased_on: @home.today - 30, left_before: 0, product_name: "Pantene 700ml" }, user: users(:alex))
    Supplies::LogPurchase.call(shampoo, { quantity: 2, total_price: 398, store: "PX Mart", purchased_on: @home.today, left_before: 1, product_name: "Lux Shampoo 750ml" }, user: users(:alex))
    shampoo.reload
  end

  test "several brands in stock: the cards show each brand's number, an All row only the category, and −1 asks which one" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = two_brands
    paper = create_item
    counts = household_supply_counts_path(@home, shampoo)
    assert_equal 3, shampoo.level

    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id}" do
      assert_select "p", text: /Lux Shampoo 750ml · /, count: 0, msg: "under the name: the category, not each brand's number"
      assert_select "a + p", "盥洗用品"
      assert_select "details summary[aria-label='Shampoo 用掉 1 瓶']", "用掉 1 瓶"
      assert_select "details p", "用掉哪一個？"
      assert_select "details form[action=?]", counts, 2
      assert_select "details form:first-of-type button", /Pantene 700ml\s+最早買的.*剩 1 · .*購買 · Coupang/m
      assert_select "details form:first-of-type input[name=product][value='Pantene 700ml']"
      assert_select "details form:last-of-type button", /Lux Shampoo 750ml.*剩 2 · .*購買 · PX Mart/m
      assert_select "details form:last-of-type button", text: /最早買的/, count: 0
      assert_select "form[action=?]", counts, 2, "no one-tap −1 beside the menu"
    end
    assert_select "#row_supply_#{paper.id} details", 0, "one brand: −1 stays a single tap"
    assert_select "#row_supply_#{paper.id} form[action=?]", household_supply_counts_path(@home, paper), 1
    assert_select "#row_supply_#{paper.id} form[action=?] button", household_supply_counts_path(@home, paper), "用掉 1 捲"
    assert_select "#row_supply_#{paper.id} a[href=?]", new_household_supply_purchase_path(@home, paper), "補貨", "the same name as on the cards and the item's page: it opens the same form"

    shampoo.favorites.create!(user: users(:alex))
    get household_supplies_path(@home, tab: "favorites")
    assert_select "#card_supply_#{shampoo.id}" do
      assert_select "p", "2 Lux Shampoo 750ml · 1 Pantene 700ml"
      assert_select "details form input[name=product]", 2
    end

    # the bottle goes from the brand picked, and from the item's one count
    post counts, params: { used_one: 1, product: "Lux Shampoo 750ml" }, as: :turbo_stream
    assert_response :success
    assert_match "用掉 1（Lux Shampoo 750ml）· 剩 2 瓶", response.body
    assert_equal 2, shampoo.reload.level
    assert_equal "Lux Shampoo 750ml", shampoo.counts.order(:id).last.used_product
    assert_equal [ [ "Pantene 700ml", 1 ], [ "Lux Shampoo 750ml", 1 ] ], shampoo.brands.list.map { [ it.name, it.known ] }
    assert_match "1</strong> Lux Shampoo 750ml · <strong class=\"text-gray-900\">1</strong> Pantene 700ml", response.body

    # Undo puts it back on that brand
    delete household_supply_count_path(@home, shampoo, shampoo.counts.order(:id).last), as: :turbo_stream
    assert_equal [ 1, 2 ], shampoo.reload.brands.list.map(&:known)

    # the last Pantene: one brand left, so the menu is gone and −1 is a single tap again
    post counts, params: { used_one: 1, product: "Pantene 700ml" }, as: :turbo_stream
    assert_equal [ [ "Lux Shampoo 750ml", 2 ] ], shampoo.reload.brands.list.map { [ it.name, it.known ] }
    assert_no_match "用掉哪一個", response.body
    assert_no_match "Pantene 700ml</p>", response.body

    # an old page still offering Pantene: refused, nothing taken from Lux instead
    assert_no_difference -> { shampoo.counts.count } do
      post counts, params: { used_one: 1, product: "Pantene 700ml" }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_match "這個品牌已經沒有庫存了", response.body
    post counts, params: { used_one: 1 }, as: :turbo_stream
    assert_equal 1, shampoo.reload.level
    assert_nil shampoo.counts.order(:id).last.used_product
  end

  test "brands with expiry dates: the one that expires first is on top, tagged, with the dates on each line" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = two_brands
    pantene, lux = shampoo.purchases.order(:id).to_a
    pantene.update!(expires_on: @home.today + 600)
    lux.update!(expires_on: @home.today + 100)

    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id}" do
      assert_select "h3 + ul li:first-child", /Lux Shampoo 750ml\s+最快到期.*#{I18n.l(lux.expires_on, format: :supply_date, locale: :"zh-TW")} 到期 · .*購買 · PX Mart · 每瓶 NT\$199/m
      assert_select "h3 + ul li:last-child", /Pantene 700ml.*#{I18n.l(pantene.expires_on, format: :supply_date, locale: :"zh-TW")} 到期 · .*購買 · Coupang/m
      assert_select "h3 + ul li:last-child", text: /最快到期|最早買的/, count: 0
      assert_select "details > summary + form label:first-of-type", /Lux Shampoo 750ml/, "Inventory lists them in the same order"
    end
    assert_select "#history_supply_#{shampoo.id} li", /Lux Shampoo 750ml\s+#{I18n.l(lux.expires_on, format: :supply_date, locale: :"zh-TW")} 到期/, "History writes the expiry date with its year"
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type button", /Lux Shampoo 750ml\s+最快到期.*剩 2 · .*到期 · .*購買/m
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type button", text: /PX Mart/, count: 0, msg: "with an expiry date the menu's line drops the store"

    lux.update!(expires_on: @home.today - 1)
    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id} h3 + ul li:first-child", /Lux Shampoo 750ml\s+已過期.*#{I18n.l(lux.expires_on, format: :supply_date, locale: :"zh-TW")} 已過期/m

    paper = create_item
    get household_supply_path(@home, paper)
    assert_select "section#forecast_supply_#{paper.id} details", 0, "one brand: Inventory stays an open line"
    assert_select "section#forecast_supply_#{paper.id} input[name='supply_count[level]']"
  end

  test "Product or brand set to the item's own name: a note says it is saved without a brand, and it is" do
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0)
    purchase = Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 145, purchased_on: @home.today, left_before: 0 }, user: users(:alex))
    note = "這是品項本身的名稱，所以這筆購買會存成未填品牌。輸入其他名稱才會成為一個品牌。"

    get new_household_supply_purchase_path(@home, shampoo)
    assert_select "[data-controller=brand-name][data-brand-name-item-value=Shampoo] p[data-brand-name-target=note][hidden]", note
    get new_household_supply_purchase_path(@home, shampoo, product_name: "Shampoo")
    assert_select "p[data-brand-name-target=note]:not([hidden])", note

    get edit_household_supply_path(@home, shampoo)
    assert_select "[data-controller=brand-name] p[data-brand-name-target=note][hidden]", note
    base = { supply: { name: "Shampoo", supply_category_id: shampoo.supply_category_id, unit: "bottle", lead_days: shampoo.lead_days, alert_when_left: 0 } }
    patch household_supply_path(@home, shampoo), params: base.merge(purchase: { purchased_on: @home.today, quantity: 1, total_price: 145, currency: "TWD", product_name: " Shampoo " })
    assert_nil purchase.reload.product_name, "the item's own name is no brand"
    patch household_supply_path(@home, shampoo), params: base.merge(purchase: { purchased_on: @home.today, quantity: 1, total_price: 145, currency: "TWD", product_name: "Lux Shampoo 750ml" })
    assert_equal "Lux Shampoo 750ml", purchase.reload.product_name
  end

  test "one brand restocked before it ran out: the form names what is left, Saved says which to use first, and each batch has its own −1" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    lux = "Lux Shampoo 750ml"
    old_date, new_date = @home.today + 100, @home.today + 400
    old = Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 189, store: "Costco", purchased_on: @home.today - 60, left_before: 0, product_name: lux, expires_on: old_date }, user: users(:alex))
    date = ->(day) { I18n.l(day, format: :supply_date, locale: :"zh-TW") }

    get new_household_supply_purchase_path(@home, shampoo)
    assert_select "p.bg-sky-50", /你還有 #{lux} 1 瓶（#{date.(old_date)} 到期）/

    post household_supply_purchases_path(@home, shampoo), params: { supply_purchase: { product_name: lux, quantity: 2, total_price: 358, store: "Costco", purchased_on: @home.today, expires_on: new_date, left_before: 1 } }
    assert_redirected_to household_supply_path(@home, shampoo)
    follow_redirect!
    assert_select "#notice", /已記錄 Shampoo 2 瓶。/
    assert_select "#notice span", "先用 #{date.(old_date)}到期的那 1 瓶；新買的 #{date.(new_date)}到期。"
    new = shampoo.purchases.order(:id).last
    assert_select "section#forecast_supply_#{shampoo.id}" do
      assert_select "h3", "依到期日"
      assert_select "h3 + ul > li", 2
      assert_select "h3 + ul > li:first-child", /#{date.(old_date)} 到期\s+最快到期.*購買 · Costco.*1 瓶/m
      assert_select "h3 + ul > li:last-child", /#{date.(new_date)} 到期.*2 瓶/m
      assert_select "h3 + ul > li:last-child form input[name=batch][value='#{new.id}']"
    end

    counts = household_supply_counts_path(@home, shampoo)
    post counts, params: { used_one: 1, batch: new.id }, as: :turbo_stream
    assert_match "用掉 1 · #{date.(new_date)} 到期 · 剩 2 瓶", response.body
    assert_equal [ [ old, 1 ], [ new, 1 ] ], shampoo.reload.brands.batches.map { [ it.purchase, it.left ] }
    assert_equal new, shampoo.counts.order(:id).last.used_purchase

    post counts, params: { used_one: 1, batch: new.id }, as: :turbo_stream
    assert_no_difference -> { shampoo.counts.count } do
      post counts, params: { used_one: 1, batch: new.id }, as: :turbo_stream
    end
    assert_response :unprocessable_content
    assert_match "這一批已經沒有庫存了", response.body
  end

  test "a restock that expires before what was left: Saved says to use the new ones first; no date: the old ones stay first" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 189, purchased_on: @home.today - 60, left_before: 0, expires_on: @home.today + 100 }, user: users(:alex))
    date = ->(day) { I18n.l(day, format: :supply_date, locale: :"zh-TW") }

    post household_supply_purchases_path(@home, shampoo), params: { supply_purchase: { quantity: 2, total_price: 358, purchased_on: @home.today, expires_on: @home.today + 50, left_before: 1 } }
    follow_redirect!
    assert_select "#notice span", "先用這次買的 2 瓶：#{date.(@home.today + 50)}到期，比你原本的 1 瓶（#{date.(@home.today + 100)}到期）還早。"

    post household_supply_purchases_path(@home, shampoo), params: { supply_purchase: { quantity: 1, total_price: 189, purchased_on: @home.today, left_before: 3 } }
    follow_redirect!
    assert_select "#notice span", "#{date.(@home.today + 50)}到期的那 2 瓶 仍然要先用。"

    plain = create_item(name: "Soap", unit: "piece", level: 1)
    post household_supply_purchases_path(@home, plain), params: { supply_purchase: { quantity: 1, total_price: 30, purchased_on: @home.today, left_before: 1 } }
    follow_redirect!
    assert_select "#notice span", 0, "no expiry dates: nothing to add under Saved"
  end

  test "two brands, one bought twice: its batches are listed under it, each with a −1, and it has none of its own" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = two_brands
    Supplies::LogPurchase.call(shampoo, { quantity: 2, total_price: 398, store: "PX Mart", purchased_on: @home.today, left_before: 3, product_name: "Lux Shampoo 750ml", expires_on: @home.today + 300 }, user: users(:alex))
    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id}" do
      assert_select "h3", "各品牌庫存"
      assert_select "h3 + ul > li", 2
      lux = shampoo.reload.brands.list.find { it.name == "Lux Shampoo 750ml" }
      assert_equal 2, lux.batches.size
      assert_select "h3 + ul > li ul > li", 2
      assert_select "h3 + ul > li ul > li form input[name=batch]", 2
      assert_select "h3 + ul > li form input[name=product][value='Lux Shampoo 750ml']", 0
      assert_select "h3 + ul > li form input[name=product][value='Pantene 700ml']", 1
    end
  end

  test "an item's page with several brands: In stock by brand, a −1 for each, Inventory by brand, and History names the brand" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = two_brands
    counts = household_supply_counts_path(@home, shampoo)

    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id}" do
      assert_select "h3", "各品牌庫存"
      assert_select "h3 + ul li", 2
      assert_select "h3 + ul li:first-child", /Pantene 700ml\s+最早買的.*購買 · Coupang · 每瓶 NT\$145.*1 瓶/m
      assert_select "h3 + ul li:first-child form[action=?] input[name=product][value='Pantene 700ml']", counts
      assert_select "h3 + ul li:last-child", /Lux Shampoo 750ml.*PX Mart · 每瓶 NT\$199.*2 瓶/m
      assert_select "details:not([open]) > summary", /盤點\s+更新數量/, "Inventory is one closed line"
      assert_select "details > summary + form label", 2
      assert_select "details label:first-of-type", /Pantene 700ml.*瓶/m
      assert_select "details input[name='supply_count[brands][][name]'][value='Pantene 700ml'] + input[name='supply_count[brands][][left]'][value='1']"
      assert_select "details input[name='supply_count[brands][][name]'][value='Lux Shampoo 750ml'] + input[name='supply_count[brands][][left]'][value='2']"
      assert_select "input[name='supply_count[level]']", 0
      assert_select "details p", "用掉哪一個？"
    end

    post counts, params: { used_one: 1, product: "Pantene 700ml" }, as: :turbo_stream
    assert_match "用掉 1 · <span class=\"font-semibold\">Pantene 700ml</span> · 剩 2 瓶", response.body
    assert_no_match "各品牌庫存", response.body

    # Inventory, one number per brand: the count is their sum
    post counts, params: { supply_count: { brands: [ { name: "Pantene 700ml", left: "2" }, { name: "Lux Shampoo 750ml", left: "3" } ] } }, as: :turbo_stream
    assert_response :success
    assert_equal 5, shampoo.reload.level
    assert_equal({ "Pantene 700ml" => 2, "Lux Shampoo 750ml" => 3 }, shampoo.counts.order(:id).last.by_product)
    assert_equal [ [ "Pantene 700ml", 2 ], [ "Lux Shampoo 750ml", 3 ] ], shampoo.brands.list.map { [ it.name, it.known ] }
    assert_match "各品牌庫存", response.body

    post counts, params: { supply_count: { brands: [ { name: "Pantene 700ml", left: "1.5" }, { name: "Lux Shampoo 750ml", left: "3" } ] } }, as: :turbo_stream
    assert_response :unprocessable_content
    post counts, params: { supply_count: { brands: [ { name: "Not a brand of it", left: "9" } ] } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_equal 5, shampoo.reload.level

    # a viewer sees each brand's number, with nothing to press
    sign_in_as users(:google_only)
    get household_supply_path(@home, shampoo)
    assert_select "h3", "各品牌庫存"
    assert_select "h3 + ul li", 2
    assert_select "form[action=?]", counts, 0
    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} details", 0
    post counts, params: { used_one: 1, product: "Pantene 700ml" }
    assert_response :forbidden
  end

  test "Used 1 on one brand in two batches asks which batch, by expiry date, and the toast names it" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    drink = create_item(name: "Sports drink", unit: "bottle", level: 0)
    older = Supplies::LogPurchase.call(drink, { quantity: 24, total_price: 385, store: "Coupang", purchased_on: @home.today - 30, left_before: 0,
                                                expires_on: @home.today + 90, product_name: "Super Supau 590ml" }, user: users(:alex))
    travel(-1.day) { Supplies::RecordCount.call(drink, 4, user: users(:alex)) }
    newer = Supplies::LogPurchase.call(drink.reload, { quantity: 24, total_price: 348, store: "酷澎", purchased_on: @home.today, left_before: 4,
                                                       expires_on: @home.today + 170, product_name: "Super Supau 590ml" }, user: users(:alex))

    [ household_supplies_path(@home, tab: "all"), household_supply_path(@home, drink) ].each do |path|
      get path
      assert_select "details summary", /用掉 1 瓶/
      assert_select "details form input[name=batch]", 2
      assert_select "details form:first-of-type input[name=batch][value=?]", older.id.to_s
      assert_select "details form:first-of-type button", /到期\s+最快到期.*剩 4 · .*購買 · Coupang/m
      assert_select "details form:last-of-type input[name=batch][value=?]", newer.id.to_s
      assert_select "details form:last-of-type button", /剩 24 · .*購買 · 酷澎/m
    end

    post household_supply_counts_path(@home, drink), params: { used_one: 1, batch: newer.id }, as: :turbo_stream
    assert_match(/用掉 1 · .*到期 · 剩 27/, response.body)
    assert_equal [ [ older.id, 4 ], [ newer.id, 23 ] ], drink.reload.brands.batches.map { [ it.purchase.id, it.left ] }
  end

  test "Used 1 with two brands, one in two batches: that brand gets a line per batch, the other one line" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0)
    Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 189, purchased_on: @home.today - 60, left_before: 0, product_name: "Pantene 700ml" }, user: users(:alex))
    first_lux = Supplies::LogPurchase.call(shampoo.reload, { quantity: 2, total_price: 300, purchased_on: @home.today - 30, left_before: 1,
                                                             expires_on: @home.today + 100, product_name: "Lux 750ml" }, user: users(:alex))
    travel(-1.day) { Supplies::RecordCount.by_brand(shampoo.reload, { "Pantene 700ml" => 1, "Lux 750ml" => 1 }, user: users(:alex)) }
    Supplies::LogPurchase.call(shampoo.reload, { quantity: 2, total_price: 300, purchased_on: @home.today, left_before: 2,
                                                 expires_on: @home.today + 400, product_name: "Lux 750ml" }, user: users(:alex))

    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} details form", 3
    assert_select "#row_supply_#{shampoo.id} details form input[name=batch]", 2
    assert_select "#row_supply_#{shampoo.id} details form input[name=product][value=?]", "Pantene 700ml"
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type input[name=batch][value=?]", first_lux.id.to_s
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type button", /Lux 750ml\s+最快到期.*到期 · 剩 1 · .*購買/m
  end

  test "a purchase with no product is a brand of its own, shown as the item's name" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    Supplies::LogPurchase.call(shampoo, { quantity: 1, total_price: 145, purchased_on: @home.today - 30, left_before: 0 }, user: users(:alex))
    Supplies::LogPurchase.call(shampoo, { quantity: 2, total_price: 398, purchased_on: @home.today, left_before: 1, product_name: "Lux Shampoo 750ml" }, user: users(:alex))

    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{shampoo.id} details form:last-of-type button", /Lux Shampoo 750ml.*剩 2/m
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type button", /Shampoo\s+最快到期|Shampoo\s+最早買的/m
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type button", /剩 1/
    assert_select "#row_supply_#{shampoo.id} details form:first-of-type input[name=product][value='']"
    assert_no_match "未填品牌", response.body
    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id} h3 + ul > li:first-child", /\AShampoo\s+最早買的/

    post household_supply_counts_path(@home, shampoo), params: { used_one: 1, product: "" }, as: :turbo_stream
    assert_match "用掉 1 · 剩 2 瓶", response.body
    assert_equal "", shampoo.counts.order(:id).last.used_product
    assert_equal [ [ "Lux Shampoo 750ml", 2 ] ], shampoo.reload.brands.list.map { [ it.name, it.known ] }
    get household_supply_path(@home, shampoo)
    assert_select "li", /數量：2 瓶/
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
    assert_select "select[name='invoices[0][lines][0][choice]'] optgroup", 2, "one category in use, then Add as new"
    assert_select "select[name='invoices[0][lines][0][choice]'] optgroup option[value=new]"
    assert_select "span", text: "建議"
    assert_select "dialog[data-controller=notice] h2", "1 項找不到", "鮮奶 matches nothing"
    assert_select "div[data-receipt-line-target=box][hidden] input[name='invoices[0][lines][1][name]'][value=鮮奶]", 1, "opens on Add as new supply…"
    assert_select "select[name='invoices[0][lines][1][supply_category_id]'] option", 7, "the six, then ＋ New category…"
    assert_select "select[name='invoices[0][lines][1][supply_category_id]'] option[selected]", "其他"
    assert_select "span", text: "找不到"
    assert_select "input[type=checkbox][name='invoices[0][lines][2][add]']:not([checked])", 1, "shipping starts unticked"
    assert_select "input[type=checkbox][name='invoices[0][lines][0][add]'][checked]"
    assert_select "select option[value=skip]", 0, "Skip is the tick box now, not a choice in the menu"
    assert_select "p[data-receipt-line-target=off]:not([hidden])", "運費等 · 不加入"
    assert_select "input[type=date][name='invoices[0][lines][0][expires_on]']"
    assert_select "span[data-receipt-pick-target=count]", "3 行中會加入 2 行"
    assert_select "span[data-receipt-pick-target=save]", "儲存 2 項"
    assert_select "span", text: "運費等 · 略過"
    assert_select "input[name='invoices[0][lines][1][quantity]'][value='2']"

    assert_difference -> { @home.records.count } => 1, -> { @home.supply_purchases.count } => 2 do
      post receipt_household_supplies_path(@home), params: { source: "qr", left:, add_to_ledger: "1",
        invoices: { "0" => { store: "全聯", lines: { "0" => { choice: supply.id, quantity: 1, units_per_line: 12 },
                                                    "1" => { choice: "new", quantity: 3, name: "鮮奶", supply_category_id: category("food_drink").id, unit: "bottle", units_per_line: 1 },
                                                    "2" => { choice: "skip" } } } } }
    end
    assert_redirected_to household_supplies_path(@home)
    assert_match "已從1 張發票儲存 2 筆購買，並在帳本記了 1 筆支出", flash[:notice]
    assert_equal 283, @home.records.order(:id).last.amount_paid
    assert_equal 4 + 12, supply.reload.level
    assert_equal "舒潔衛生紙", supply.purchases.sole.product_name, "the receipt line's text is the product bought"
    assert_equal 3, @home.supplies.find_by!(name: "鮮奶").level, "the quantity typed on the review wins"
    assert_equal "food_drink", @home.supplies.find_by!(name: "鮮奶").category.key, "a new item goes in the category picked on the review"
    assert_equal "全聯", @home.receipt_sellers.sole.name

    post receipt_review_household_supplies_path(@home), params: { source: "qr", left: }
    assert_redirected_to scan_household_supplies_path(@home, mode: "receipt")
    assert_match "已經在", flash[:alert]
    assert_match(/品項在.*衛生紙/, flash[:alert], "and says where its items are")

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
      assert_select "input[type=checkbox][name='invoices[0][lines][1][add]']:not([checked])"
      assert_select "input[name='invoices[0][lines][0][quantity]'][value='2']"
    end
    assert_select "h2#not_included_title", "沒有加入（3）"
    assert_match "跟上面是同一張", response.body
    assert_match "無法讀取", response.body
    assert_match "這個 PDF 裡沒有品項", response.body
    assert_select "input[type=hidden][name='pdfs[0][words]']"

    assert_difference -> { @home.supply_purchases.count } => 1, -> { @home.records.count } => 1 do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
        invoices: { "0" => { store: "徠樂", lines: { "0" => { add: "1", choice: cleaner.id, quantity: 2, units_per_line: 1, expires_on: "2028-01-15" },
                                                  "1" => { add: "0", choice: cleaner.id } } },
                    "3" => { ledger_total: "1", store: "某某商店" } } }
    end
    assert_equal [ [ 2, 120, "徠樂", Date.new(2028, 1, 15) ] ], cleaner.purchases.map { [ it.quantity, it.total_price.to_i, it.store, it.expires_on ] },
                 "the unticked line is skipped, whatever its menu says; the ticked one keeps its expiry date"
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

  test "pack size per brand: Brand A in packs of 4 and Brand B in packs of 20, each with its own price per piece" do
    snack = create_item(name: "寵物零食", unit: "pack", level: 0)
    get edit_household_supply_path(@home, snack)
    assert_select "form[data-controller~=pack-size]"
    assert_select "input[name='supply[pack_size]']", 0
    assert_select "[data-pack-size-target=row]:not([hidden]) input[name='purchase[pack_size]']:not([disabled])"

    get new_household_supply_purchase_path(@home, snack)
    assert_select "form[data-controller='paid-currency pack-size'][data-pack-size-sizes-value='{}']"
    assert_select "[data-pack-size-target=row] [data-pack-size-target=label]", "每包有"
    assert_select "select[name='supply_purchase[pack_unit]'] option", 4
    post household_supply_purchases_path(@home, snack), params: { supply_purchase: { product_name: "Brand A", quantity: 6, total_price: 360, store: "Costco", purchased_on: @home.today - 10, pack_size: 4, pack_unit: "piece" } }
    post household_supply_purchases_path(@home, snack), params: { supply_purchase: { product_name: "Brand B", quantity: 2, total_price: 480, store: "全聯", purchased_on: @home.today, pack_size: 20 } }
    assert_equal [ [ "Brand A", 4 ], [ "Brand B", 20 ] ], snack.purchases.order(:purchased_on).pluck(:product_name, :pack_size)

    get household_supply_path(@home, snack)
    assert_select "span", "· 共 64 個"
    assert_select "li span.text-right", text: /6 包\s*（24 個）/
    assert_select "li span.text-right", text: /2 包\s*（40 個）/
    assert_match "全聯 最便宜：每包 NT$240 · 每個 NT$12", response.body
    assert_match "最低每包 NT$240 · 每個 NT$12", response.body
    assert_match "每包 NT$60 · 每個 NT$15", response.body
    assert_match "用掉 1 包", response.body # a menu of the two brands

    # Bought again: the form knows each brand's size, and fills in the last one's
    get new_household_supply_purchase_path(@home, snack)
    assert_equal({ "Brand A" => [ 4, "piece" ], "Brand B" => [ 20, "piece" ] }, JSON.parse(css_select("form[data-pack-size-sizes-value]").first["data-pack-size-sizes-value"]))
    get new_household_supply_price_path(@home, snack)
    assert_select "input[name='supply_price[pack_size]']"
    get edit_household_supply_path(@home, snack)
    assert_select "input[name='purchase[pack_size]'][value='20']"

    # Counted in pieces: the sizes are set aside, and come back with packs
    patch household_supply_path(@home, snack), params: { supply: { unit: "piece", supply_category_id: snack.supply_category_id } }
    get household_supply_path(@home, snack)
    assert_no_match "每個 NT$12", response.body
    assert_no_match "共 64", response.body
    get edit_household_supply_path(@home, snack)
    assert_select "[data-pack-size-target=row][hidden] input[name='purchase[pack_size]'][disabled]"
    patch household_supply_path(@home, snack), params: { supply: { unit: "pack", supply_category_id: snack.supply_category_id } }
    get household_supply_path(@home, snack)
    assert_select "span", "· 共 64 個"
  end

  test "pack size: an item in packs with no sizes looks as before" do
    tissues = create_item(name: "面紙", unit: "pack", level: 0)
    post household_supply_purchases_path(@home, tissues), params: { supply_purchase: { quantity: 6, total_price: 360, store: "Costco", purchased_on: @home.today } }
    get household_supply_path(@home, tissues)
    assert_match "最低每包 NT$60", response.body
    assert_no_match "每個 NT$", response.body
    assert_no_match "· 共", response.body
  end

  test "invoice PDFs: Add as new supply opens a New supply box whose Category can be a new one, made on Save and listed in Settings" do
    SupplyCategory.seed(@home)
    pdfs = { "0" => { name: "a.pdf", words: file_fixture("einvoice/invoice_pdf_words.json").read } }
    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: }
    assert_select "li[data-controller=receipt-line]", 2
    assert_select "select[name='invoices[0][lines][0][choice]'][data-receipt-line-target=choice] option[value=new]", "新增為日用品…"
    assert_select "div[data-receipt-line-target=box][hidden]", 2 # nothing chosen yet: no new-supply fields
    assert_select "select[name='invoices[0][lines][0][supply_category_id]'] option:last-child[value=new]", "＋ 新增類別…"
    assert_select "div[data-new-category-target=field][hidden] input[name='invoices[0][lines][0][new_category_name]']"
    assert_select "label[for=invoice_0_line_0_name]", "名稱"

    line = { choice: "new", name: "馬桶清潔劑", supply_category_id: "new", unit: "bottle", quantity: 2, units_per_line: 1 }
    # "＋ New category…" with no name: nothing is saved, the line comes back in red with its box open
    assert_no_difference -> { @home.supply_categories.count } => 0, -> { @home.supplies.count } => 0, -> { @home.receipt_imports.count } => 0 do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
        invoices: { "0" => { store: "徠樂", lines: { "0" => line.merge(new_category_name: " "), "1" => { choice: "skip" } } } } }
    end
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /還有 1 項要完成/
    assert_select "div[data-receipt-line-target=box]:not([hidden]) input[name='invoices[0][lines][0][new_category_name]'][aria-invalid=true][required][autofocus]"
    assert_select "p", "請輸入新類別的名稱。"
    assert_select "input[name='invoices[0][lines][0][name]'][value=馬桶清潔劑]"

    assert_difference -> { @home.supply_categories.count } => 1, -> { @home.supplies.count } => 1 do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
        invoices: { "0" => { store: "徠樂", lines: { "0" => line.merge(new_category_name: " 浴室用品 "), "1" => { choice: "skip" } } } } }
    end
    bathroom = @home.supply_categories.order(:id).last
    assert_equal [ "浴室用品", nil ], [ bathroom.name_zh, bathroom.name_en ]
    assert_equal @home.supply_categories.where.not(id: bathroom.id).maximum(:position) + 1, bathroom.position
    supply = @home.supplies.find_by!(name: "馬桶清潔劑")
    assert_equal [ bathroom, "bottle", 2 ], [ supply.category, supply.unit, supply.purchases.sole.quantity ]
    assert_match "新類別：浴室用品（在「設定 › 類別」）。", flash[:notice]
    get household_categories_path(@home)
    assert_match "浴室用品", response.body
  end

  test "invoice PDFs: a new category named like one the ledger has uses that one" do
    SupplyCategory.seed(@home)
    pdfs = { "0" => { name: "a.pdf", words: file_fixture("einvoice/invoice_pdf_words.json").read } }
    assert_no_difference -> { @home.supply_categories.count } do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
        invoices: { "0" => { lines: { "0" => { choice: "new", name: "馬桶清潔劑", supply_category_id: "new", new_category_name: "cleaning", quantity: 1, units_per_line: 1 },
                                      "1" => { choice: "skip" } } } } }
    end
    assert_equal category("cleaning"), @home.supplies.find_by!(name: "馬桶清潔劑").category
    assert_no_match "新類別", flash[:notice]
  end

  test "invoice PDFs after a combine: Save keeps every line, the brand is known, and the same invoice says where its items are now" do
    brand = create_item(name: "魔術靈馬桶清潔劑", unit: "bottle")
    cleaner = create_item(name: "Toilet cleaner", unit: "bottle")
    words = file_fixture("einvoice/invoice_pdf_words.json").read
    pdfs = { "0" => { name: "a.pdf", words: } }

    # A line left on Choose…: nothing is saved, and the review comes back as it was left
    assert_no_difference -> { @home.receipt_imports.count } do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:, add_to_ledger: "1",
        invoices: { "0" => { store: "徠樂", lines: { "0" => { choice: "", quantity: 3, units_per_line: 1 }, "1" => { choice: "skip" } } } } }
    end
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /還有 1 項要完成/
    assert_select "select[name='invoices[0][lines][0][choice]'][aria-invalid=true][autofocus] option[selected][value='']"
    assert_select "p", "請選擇，或取消勾選"
    assert_select "select[name='invoices[0][lines][1][choice]']:not([aria-invalid])"
    assert_select "input[type=checkbox][name='invoices[0][lines][1][add]']:not([checked])"
    assert_select "input[name='invoices[0][lines][0][quantity]'][value='3']"
    assert_select "input[name='invoices[0][store]'][value=徠樂]"
    assert_select "input[name=add_to_ledger][checked]"

    # An excluded invoice isn't checked
    assert_no_difference -> { @home.receipt_imports.count } do
      post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:, invoices: { "0" => { exclude: "1", lines: { "0" => { choice: "" } } } } }
    end
    assert_redirected_to household_supplies_path(@home)

    post receipt_household_supplies_path(@home), params: { source: "pdf", pdfs:,
      invoices: { "0" => { store: "徠樂", lines: { "0" => { choice: brand.id, quantity: 2, units_per_line: 1 }, "1" => { choice: "skip" } } } } }
    assert_redirected_to household_supplies_path(@home)
    Supplies::Combine.call(brand.reload, into: cleaner.reload, user: users(:alex))

    # The same PDF again: added before, and its item is in Toilet cleaner now
    assert_no_difference -> { @home.receipt_imports.count } do
      post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: }
    end
    assert_select "[role=status]", text: /已經加入過，沒有新的東西/
    assert_match "現在在「Toilet cleaner」裡，是它的一個品牌", response.body
    assert_select "a[href=?]", household_supply_path(@home, cleaner), text: "打開Toilet cleaner ›"
    assert_select "form[action=?] button[type=submit]", receipt_household_supplies_path(@home), 0, "nothing to save"
    assert_select "a[href=?]", household_supplies_path(@home), text: "完成"

    # Another store's invoice with the same product: matched to Toilet cleaner as a brand of it
    other = { "0" => { name: "b.pdf", words: words.gsub("HX45765353", "HX45765399").gsub("85627834", "12345675") } }
    post receipt_review_household_supplies_path(@home), params: { source: "pdf", pdfs: other }
    assert_select "select[name='invoices[0][lines][0][choice]'] option[selected][value=?]", cleaner.id.to_s
    assert_select "span", text: "已知品牌"
    assert_match "Toilet cleaner的品牌：以前買過", response.body
  end

  test "a new item bought a while ago with some used: the forecast has a usage rate straight away" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon # a purchase on a past day counts from its midday
    bought_on = @home.today - 10
    post household_supplies_path(@home), params: { supply: { name: "Toilet paper", supply_category_id: category("toiletries").id, unit: "roll", level: 5 },
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
    post household_supplies_path(@home), params: { supply: { name: "Soap", supply_category_id: category("cleaning").id, unit: "bottle", level: 3 },
                                                   purchase: { quantity: 3, total_price: 150 } }
    supply = @home.supplies.sole
    assert_equal [ 3 ], supply.purchases.map(&:quantity)
    assert_empty supply.counts

    post household_supplies_path(@home), params: { supply: { name: "Rice", supply_category_id: category("food_drink").id, unit: "bag", level: 1 },
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

  test "edit: two batches of one brand in stock are both listed, with expiry and what is left, and the older one can be corrected" do
    drink = create_item(name: "Sports drink", unit: "bottle", level: 0)
    older = Supplies::LogPurchase.call(drink, { quantity: 24, total_price: 385, store: "Coupang", purchased_on: @home.today - 30, left_before: 0,
                                                expires_on: @home.today + 90, product_name: "Super Supau 590ml" }, user: users(:alex))
    Supplies::RecordCount.call(drink, 4, user: users(:alex))
    newer = Supplies::LogPurchase.call(drink.reload, { quantity: 24, total_price: 348, store: "酷澎", purchased_on: @home.today, left_before: 4,
                                                       expires_on: @home.today + 170, product_name: "Super Supau 590ml" }, user: users(:alex))

    get edit_household_supply_path(@home, drink)
    assert_select "turbo-frame#supply_purchase details[open]" do
      assert_select "summary", "修正一筆購買 · 有 2 筆可選"
      assert_select "p", "要修正哪一筆？"
      assert_select "a[aria-current=true][href=?]", edit_household_supply_path(@home, drink, purchase_id: newer.id), text: /酷澎.*到期 · 剩 24/m
      assert_select "a[href=?]", edit_household_supply_path(@home, drink, purchase_id: older.id), text: /Coupang.*到期 · 剩 4/m
    end

    get edit_household_supply_path(@home, drink, purchase_id: older.id), headers: { "Turbo-Frame" => "supply_purchase" }
    assert_select "input[name='purchase[store]'][value=Coupang]"
    patch household_supply_path(@home, drink), params: { supply: { name: "Sports drink" }, purchase_id: older.id,
      purchase: { purchased_on: older.purchased_on, quantity: 24, total_price: 380, store: "Coupang", expires_on: older.expires_on, product_name: "Super Supau 590ml" } }
    assert_redirected_to household_supply_path(@home, drink)
    assert_equal 380, older.reload.total_price
    assert_equal 348, newer.reload.total_price

    Supplies::RecordCount.call(drink.reload, 24, user: users(:alex))
    get edit_household_supply_path(@home, drink)
    assert_select "a[data-turbo-frame=supply_purchase]", 0, "the older batch is used up: only the latest is left to correct"
  end

  test "edit: an item bought as two products lists them, and the one chosen is the purchase corrected" do
    supply = create_item(name: "Coffee", unit: "bag")
    kirkland = Supplies::LogPurchase.call(supply, { quantity: 1, total_price: 529, store: "Costco", purchased_on: @home.today - 10, left_before: 0,
                                                    product_name: "Kirkland Espresso 1.13kg" }, user: users(:alex), add_to_ledger: true)
    starbucks = Supplies::LogPurchase.call(supply, { quantity: 2, total_price: 700, store: "家樂福", purchased_on: @home.today, left_before: 1,
                                                     product_name: "Starbucks House Blend" }, user: users(:alex))

    get edit_household_supply_path(@home, supply)
    assert_select "turbo-frame#supply_purchase details[open]" do
      assert_select "summary", "修正一筆購買 · 有 2 筆可選"
      assert_select "a[data-turbo-frame=supply_purchase]", 2
      assert_select "a[aria-current=true][href=?]", edit_household_supply_path(@home, supply, purchase_id: starbucks.id), text: /Starbucks House Blend/
      assert_select "a[href=?]", edit_household_supply_path(@home, supply, purchase_id: kirkland.id), text: /Kirkland Espresso 1.13kg.*Costco/m
      assert_select "input[type=hidden][name=purchase_id][value=?]", starbucks.id.to_s
      assert_select "input[name='purchase[total_price]'][value='700']"
    end

    get edit_household_supply_path(@home, supply, purchase_id: kirkland.id), headers: { "Turbo-Frame" => "supply_purchase" }
    assert_select "turbo-frame#supply_purchase" do
      assert_select "a[aria-current=true]", text: /Kirkland/
      assert_select "input[type=hidden][name=purchase_id][value=?]", kirkland.id.to_s
      assert_select "input[name='purchase[product_name]'][value=?]", "Kirkland Espresso 1.13kg"
      assert_select "p", text: /購買的 Kirkland Espresso 1.13kg/
    end

    patch household_supply_path(@home, supply), params: { supply: { name: "Coffee" }, purchase_id: kirkland.id,
      purchase: { purchased_on: kirkland.purchased_on, quantity: 1, total_price: 499, store: "Costco", product_name: "Kirkland Espresso 1.13kg" } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal 499, kirkland.reload.total_price
    assert_equal 499, kirkland.record.reload.amount_paid, "its Ledger expense follows"
    assert_equal 700, starbucks.reload.total_price, "the latest purchase is left alone"

    other = create_item(name: "Rice")
    get edit_household_supply_path(@home, supply, purchase_id: Supplies::LogPurchase.call(other, { quantity: 1, total_price: 1, purchased_on: @home.today }, user: users(:alex)).id)
    assert_response :not_found
  end

  test "edit: an item bought as one product, with the older purchase used up, has no list" do
    supply = create_item
    Supplies::LogPurchase.call(supply, { quantity: 12, total_price: 289, purchased_on: @home.today - 3, left_before: 0 }, user: users(:alex))
    Supplies::LogPurchase.call(supply, { quantity: 12, total_price: 299, purchased_on: @home.today, left_before: 0 }, user: users(:alex))
    get edit_household_supply_path(@home, supply)
    assert_select "summary", text: /上次購買/
    assert_select "a[data-turbo-frame=supply_purchase]", 0
    assert_select "input[name=purchase_id]", 0
  end

  test "edit: an item added without a purchase can get one afterwards, before its first count" do
    post household_supplies_path(@home), params: { supply: { name: "Shampoo", supply_category_id: category("toiletries").id, unit: "bottle", level: 2 } }
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

  test "Restocked with a purchase date weeks back: the stock counts from now, and the count made since isn't read as usage" do
    post household_supplies_path(@home), params: { supply: { name: "Face wash", supply_category_id: category("toiletries").id, unit: "piece", level: 0 } }
    supply = @home.supplies.sole
    post household_supply_purchases_path(@home, supply), params: { supply_purchase: { product_name: "Perfect Whip", quantity: 1, total_price: 120,
      store: "Matsukiyo", purchased_on: @home.today - 75, left_before: 1 } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal 2, supply.reload.level, "1 left before + 1 bought"
    assert_empty supply.forecast.samples, "not 2 used in 75 days"
    assert_not supply.forecast.out?

    follow_redirect!
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :forecast)}", /2 pieces now|目前 2 ?個/
    assert_select "##{ActionView::RecordIdentifier.dom_id(supply, :forecast)}", text: /Probably out|可能用完了/, count: 0

    # Correcting its date on Edit doesn't move it before that count either
    patch household_supply_path(@home, supply), params: { supply: { name: "Face wash" },
      purchase: { purchased_on: @home.today - 80, quantity: 1, total_price: 120, store: "Matsukiyo", product_name: "Perfect Whip" } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal 2, supply.reload.level
    assert_equal @home.today - 80, supply.purchases.sole.purchased_on
    assert_empty supply.forecast.samples
  end

  test "Edit › Delete item removes it for good with its history; Ledger expenses stay, and a receipt with nothing left can be added again" do
    supply = create_item
    other = create_item(name: "Dish soap")
    alex = users(:alex)
    spent = Supplies::LogPurchase.call(supply, { quantity: 12, total_price: 289, purchased_on: @home.today }, user: alex, add_to_ledger: true)
    gone = @home.receipt_imports.create!(invoice_no: "AB12345678", seller_tax_id: "12345678", issued_on: @home.today, total: 100)
    shared = @home.receipt_imports.create!(invoice_no: "AB12345679", seller_tax_id: "12345678", issued_on: @home.today, total: 200)
    Supplies::LogPurchase.call(supply, { quantity: 1, total_price: 100, purchased_on: @home.today, receipt_import: gone }, user: alex)
    Supplies::LogPurchase.call(supply, { quantity: 1, total_price: 100, purchased_on: @home.today, receipt_import: shared }, user: alex)
    Supplies::LogPurchase.call(other, { quantity: 1, total_price: 100, purchased_on: @home.today, receipt_import: shared }, user: alex)
    supply.barcodes.create!(household: @home, code: "4901234567894")
    supply.favorites.create!(user: alex)
    supply.prices.create!(household: @home, quantity: 1, total_price: 30, purchased_on: @home.today, currency: "TWD")
    match = @home.receipt_item_matches.create!(seller_tax_id: "12345678", receipt_text: "衛生紙", supply:, units_per_line: 12)

    get edit_household_supply_path(@home, supply)
    assert_select "form[action=?][data-turbo-confirm*=?]", household_supply_path(@home, supply), "要永久刪除「Toilet paper」嗎？它的記錄（3 筆購買）" do
      assert_select "input[name=_method][value=delete]"
      assert_select "button.btn-press.bg-red-100", text: /刪除品項/
    end
    assert_select "a.btn-press[href=?]", new_household_supply_combine_path(@home, supply), text: "把另一個品項合併進來"

    assert_difference -> { @home.supplies.count } => -1, -> { SupplyPurchase.count } => -3, -> { @home.records.count } => 0 do
      delete household_supply_path(@home, supply)
    end
    assert_redirected_to household_supplies_path(@home)
    follow_redirect!
    assert_select "#notice", "已刪除 Toilet paper。"
    assert @home.records.exists?(spent.record_id), "the expense stays in the Ledger"
    assert_not ReceiptItemMatch.exists?(match.id), "the store's line is asked about again, not skipped"
    assert_equal [ 0, 0, 0 ], [ SupplyBarcode.count, SupplyFavorite.count, SupplyPrice.count ]
    assert_equal [ "AB12345679" ], @home.receipt_imports.pluck(:invoice_no), "a receipt another item is still on stays"
    assert_equal 1, other.reload.purchases.size

    archived = create_item(name: "Old sponge", archived_at: Time.current)
    get edit_household_supply_path(@home, archived)
    assert_select "form[action=?] input[name=_method][value=delete]", household_supply_path(@home, archived)
    assert_select "form[data-turbo-confirm*=?]", "沒有購買記錄"
  end

  test "Edit › Combine: the item you opened is kept; the one you pick moves in as a brand, the same category first" do
    shampoo = SupplyCategory.named(@home, "洗髮精")
    promise = create_item(name: "Promise Volume Shampoo", unit: "bottle", category: shampoo, level: 0)
    keep = create_item(name: "Shampoo", unit: "bottle", category: shampoo, level: 0)
    soap = create_item(name: "Dish soap", unit: "bottle", kind: "kitchen", level: 0)
    create_item(name: "Old shampoo", category: shampoo, archived_at: Time.current)
    Supplies::LogPurchase.call(promise, { quantity: 2, total_price: 499, purchased_on: @home.today - 3 }, user: users(:alex))
    Supplies::LogPurchase.call(keep, { quantity: 3, total_price: 897, purchased_on: @home.today - 5, product_name: "PDRN Care" }, user: users(:alex))

    get edit_household_supply_path(@home, keep)
    assert_select "a.btn-press[href=?]", new_household_supply_combine_path(@home, keep), text: "把另一個品項合併進來"

    get new_household_supply_combine_path(@home, keep)
    assert_response :success
    assert_select "h1, h2", /要把哪個品項合併到「Shampoo」？/
    assert_select "p.bg-sky-50", /你選的品項會搬進「Shampoo」.*「Shampoo」的名稱和單位不變/
    assert_select "section", 2
    assert_select "section:first-of-type h3", "同一個類別（洗髮精）"
    assert_select "section:first-of-type li", 1
    assert_select "section:first-of-type form[action=?][data-turbo-confirm*=?]", household_supply_combine_path(@home, keep),
                  "要把「Promise Volume Shampoo」合併到「Shampoo」嗎？「Shampoo」會變成 3 + 2 = 5 瓶" do
      assert_select "input[name=from][value=?]", promise.id.to_s
      assert_select "button", /Promise Volume Shampoo\s*2 瓶/
    end
    assert_select "section:last-of-type li button", /Dish soap\s*0 瓶 · 廚房用品/
    assert_select "button", text: /Old shampoo|\AShampoo/, count: 0
    assert_select "p", /請打開那個品項再合併/

    post household_supply_combine_path(@home, keep), params: { from: promise.id }
    assert_redirected_to household_supply_path(@home, keep)
    follow_redirect!
    assert_select "#notice", "「Promise Volume Shampoo」現在是「Shampoo」的一個品牌。"
    assert_not Supply.exists?(promise.id)
    assert_equal [ "Shampoo", 5 ], [ keep.reload.name, keep.level ], "the item opened keeps its name"
    assert_equal({ "PDRN Care" => 3, "Promise Volume Shampoo" => 2 }, keep.brands.list.to_h { [ it.key, it.known ] })
    assert_select "##{ActionView::RecordIdentifier.dom_id(keep, :forecast)}", /Promise Volume Shampoo/

    get household_supplies_path(@home, tab: "all")
    assert_select "#row_supply_#{keep.id} details summary", /用掉 1 瓶/, "two brands in stock: it asks which one"
    get new_household_supply_combine_path(@home, soap)
    assert_select "section", 1
    assert_select "section h3", "其他品項"
  end

  test "Combine: an empty general item takes in two products and then asks which one was used" do
    face = SupplyCategory.named(@home, "洗面乳")
    general = create_item(name: "Face Wash", unit: "piece", category: face, level: 0)
    scrub = create_item(name: "Perfect Whip 去除角質", unit: "piece", category: face, level: 0)
    acne = create_item(name: "Perfect Whip 預防青春痘", unit: "piece", category: face, level: 0)
    [ scrub, acne ].each { Supplies::LogPurchase.call(it, { quantity: 1, total_price: 120, purchased_on: @home.today - 2 }, user: users(:alex)) }

    post household_supply_combine_path(@home, general), params: { from: scrub.id }
    post household_supply_combine_path(@home, general), params: { from: acne.id }

    assert_equal [ "Face Wash" ], @home.supplies.pluck(:name)
    assert_equal [ "Face Wash", 2 ], [ general.reload.name, general.level ]
    assert_equal({ "Perfect Whip 去除角質" => 1, "Perfect Whip 預防青春痘" => 1 }, general.brands.list.to_h { [ it.key, it.known ] })
    assert general.brands.several?
    get household_supply_path(@home, general)
    assert_select "##{ActionView::RecordIdentifier.dom_id(general, :forecast)}", /Perfect Whip 去除角質.*Perfect Whip 預防青春痘/m
  end

  test "a viewer can't delete or combine items, and another ledger's items aren't found" do
    supply = create_item
    other = create_item(name: "Dish soap")
    theirs = households(:parents).supplies.create!(name: "Rice", kind: "food_drink", unit: "bag", level: 1)
    post household_supply_combine_path(@home, supply), params: { from: theirs.id }
    assert_response :not_found
    post household_supply_combine_path(@home, supply), params: { from: supply.id }
    assert_response :not_found
    delete household_supply_path(@home, theirs)
    assert_response :not_found

    sign_in_as users(:google_only)
    get new_household_supply_combine_path(@home, supply)
    assert_response :forbidden
    post household_supply_combine_path(@home, supply), params: { from: other.id }
    assert_response :forbidden
    delete household_supply_path(@home, supply)
    assert_response :forbidden
    assert_equal 2, @home.supplies.count
  end

  # Bought abroad: a rate already kept for a day, so the rate service isn't asked
  def keep_rate(base, on, rate)
    ExchangeRate.create!(base:, quote: "TWD", rated_on: on, published_on: on, rate:, fetched_at: Time.current)
  end

  # The rate service can't be reached
  def without_rate_service
    real = Supplies::ExchangeRateLookup.method(:fetch)
    Supplies::ExchangeRateLookup.define_singleton_method(:fetch) { |_url| nil }
    yield
  ensure
    Supplies::ExchangeRateLookup.define_singleton_method(:fetch, real)
  end

  def face_wash = @home.supplies.create!(name: "Face Wash", kind: "toiletries", unit: "piece", level: 2)

  def dom_id(...) = ActionView::RecordIdentifier.dom_id(...)

  test "bought abroad by card: the yen price is saved in NT$ with the 1.5% card fee, and the Ledger, the lists and the item's page use it" do
    supply = face_wash
    day = @home.today - 2
    keep_rate("JPY", day, "0.20612")

    get new_household_supply_purchase_path(@home, supply)
    assert_select "form[data-controller~='paid-currency'][data-paid-currency-home-value='TWD']" do
      assert_select "select[name='supply_purchase[paid_currency]']" do
        assert_select "option", 14
        assert_select "option[selected][value='TWD']", "TWD · 新台幣"
        assert_select "optgroup[label='用過的']", 0
        assert_select "optgroup[label='其他'] option[value='JPY']", "JPY · 日圓"
      end
      assert_select "input[name='supply_purchase[total_price]'][step='1'][data-paid-currency-target='price']"
      assert_select "input[name='supply_purchase[quantity]'][data-paid-currency-target='quantity']"
      assert_select "input[name='supply_purchase[purchased_on]'][data-paid-currency-target='date']"
      # Hidden on the household's own currency: something bought at home is typed as before
      assert_select "[data-paid-currency-target='panel'][hidden]" do
        assert_select "input[name='supply_purchase[paid_by]'][value='card'][checked]"
        assert_select "input[name='supply_purchase[paid_by]'][value='cash']:not([checked])"
        assert_select "input[name='supply_purchase[card_fee_percent]'][value='1.5'][max='10']"
        assert_select "legend", "要記下的 NT$ 金額"
        assert_select "input[name='supply_purchase[card_fee_included]'][value='1'][checked]"
        assert_select "label", /不含刷卡手續費/
        assert_select "label", /含 1.5% 刷卡手續費/
        assert_select "input[name='supply_purchase[home_total]']"
        assert_select "input[name='supply_purchase[home_total_with_fee]']"
        assert_select "span", "用的是購買當天的匯率，不是今天的。改日期，匯率會跟著換。"
      end
    end

    # The rate the form shows is the one for the day it was bought
    get exchange_rate_household_supplies_path(@home, from: "JPY", on: day.iso8601)
    assert_equal({ "rate" => "0.20612", "on" => day.iso8601 }, response.parsed_body.to_h)

    assert_difference -> { @home.records.count } do
      post household_supply_purchases_path(@home, supply), params: { add_to_ledger: "1", supply_purchase: { quantity: 2, total_price: 1196, paid_currency: "JPY",
        paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1", home_total: "247", home_total_with_fee: "250", store: "松本清", purchased_on: day, left_before: 2 } }
    end
    assert_redirected_to household_supply_path(@home, supply)
    purchase = supply.purchases.sole
    assert_equal [ 250, "TWD", "JPY", 1196, BigDecimal("0.20612"), "card", BigDecimal("1.5"), true ],
                 purchase.values_at(:total_price, :currency, :paid_currency, :paid_total, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
    assert_equal [ 250, "TWD" ], purchase.record.values_at(:amount_paid, :currency), "the Ledger expense is the NT$ amount, card fee and all"

    get household_supply_path(@home, supply)
    assert_match "NT$250 買 2</span>\u00A0· <span class=\"whitespace-nowrap\">每個 NT$125", response.body
    assert_select "details##{dom_id(supply, :history)} li", /\+2 個 · NT\$250 \(JP¥1,196\) · 松本清/
    assert_select "details##{dom_id(supply, :price_history)}" do
      assert_select "li", /刷卡實付 JP¥1,196（含手續費）/
      assert_select "td", /NT\$250.*每個|NT\$250.*NT\$125\/個.*刷卡實付 JP¥1,196（含手續費）/m
    end
    get household_supplies_path(@home, tab: "all")
    assert_select "li##{dom_id(supply, :row)}", /NT\$250 買 2\u00A0· 每個 NT\$125/
    assert_select "li##{dom_id(supply, :row)}", text: /JP¥/, count: 0
  end

  test "bought abroad: the amount without the card fee, a 3% fee, and cash; the next form opens on what was chosen last" do
    supply = face_wash
    day = @home.today - 2
    keep_rate("JPY", day, "0.20612")
    bought = { quantity: 2, total_price: 1196, paid_currency: "JPY", store: "松本清", purchased_on: day, left_before: 0 }

    post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(paid_by: "card", card_fee_percent: "3", card_fee_included: "1", home_total: "247", home_total_with_fee: "254") }
    assert_equal [ 254, BigDecimal("3"), true ], supply.purchases.order(:id).last.values_at(:total_price, :card_fee_percent, :card_fee_included)

    travel 1.minute
    post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(paid_by: "card", card_fee_percent: "3", card_fee_included: "0", home_total: "247", home_total_with_fee: "254") }
    assert_equal [ 247, BigDecimal("3"), false, BigDecimal("0.20612") ], supply.purchases.order(:id).last.values_at(:total_price, :card_fee_percent, :card_fee_included, :exchange_rate)
    get household_supply_path(@home, supply)
    assert_select "details##{dom_id(supply, :price_history)} li", /刷卡實付 JP¥1,196（不含手續費）/

    get new_household_supply_purchase_path(@home, supply)
    assert_select "select[name='supply_purchase[paid_currency]']" do
      assert_select "option[selected][value='TWD']"
      assert_select "optgroup[label='用過的'] option[value='JPY']"
      assert_select "optgroup[label='其他'] option[value='JPY']", 0
      assert_select "option", 14
    end
    assert_select "input[name='supply_purchase[paid_by]'][value='card'][checked]"
    assert_select "input[name='supply_purchase[card_fee_percent]'][value='3']"
    assert_select "input[name='supply_purchase[card_fee_included]'][value='0'][checked]"
    assert_select "label", /含 3% 刷卡手續費/

    travel 1.minute
    post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(paid_by: "cash", home_total: "247") }
    assert_equal [ 247, "cash", nil, nil, BigDecimal("0.20612") ], supply.purchases.order(:id).last.values_at(:total_price, :paid_by, :card_fee_percent, :card_fee_included, :exchange_rate)
    get household_supply_path(@home, supply)
    assert_select "details##{dom_id(supply, :price_history)} li", /現金實付 JP¥1,196/
    get new_household_supply_purchase_path(@home, supply)
    assert_select "input[name='supply_purchase[paid_by]'][value='cash'][checked]"
    assert_select "input[name='supply_purchase[card_fee_percent]'][value='3']", 1, "the card's fee is kept for the next card purchase"
  end

  test "bought abroad: an amount typed over the app's is saved as typed; with no rate the form asks for the amount" do
    supply = face_wash
    day = @home.today - 2
    keep_rate("JPY", day, "0.20612")
    bought = { quantity: 2, total_price: 1196, paid_currency: "JPY", store: "松本清", left_before: 0 }

    post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(purchased_on: day, paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1", home_total: "247", home_total_with_fee: "252") }
    assert_equal [ 252, nil, 1196 ], supply.purchases.sole.values_at(:total_price, :exchange_rate, :paid_total)

    without_rate_service do
      get exchange_rate_household_supplies_path(@home, from: "JPY", on: (day - 1).iso8601)
      assert_equal({ "rate" => nil }, response.parsed_body.to_h)

      assert_no_difference -> { supply.purchases.count } do
        post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(purchased_on: day - 1, paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1") }
      end
      assert_response :unprocessable_content
      assert_select "ul li", "目前查不到 JPY 的匯率。請輸入要記下的 NT$ 金額。"
      # Sent back as it was typed: yen in the price box, the panel open
      assert_select "select[name='supply_purchase[paid_currency]'] option[selected][value='JPY']"
      assert_select "input[name='supply_purchase[total_price]'][value='1196']"
      assert_select "[data-paid-currency-target='panel']:not([hidden])"

      travel 1.minute
      post household_supply_purchases_path(@home, supply), params: { supply_purchase: bought.merge(purchased_on: day - 1, paid_by: "card", home_total: "250") }
      assert_redirected_to household_supply_path(@home, supply)
      assert_equal [ 250, 1196, nil, "card", nil, nil ], supply.purchases.order(:id).last.values_at(:total_price, :paid_total, :exchange_rate, :paid_by, :card_fee_percent, :card_fee_included)
    end
    get household_supply_path(@home, supply)
    # No fee was worked out, so the line says neither "with fee" nor "without fee"
    assert_select "details##{dom_id(supply, :price_history)} li", /NT\$250.*刷卡實付 JP¥1,196(?!（)/m
  end

  test "bought abroad: Edit switches the latest purchase to yen and back, and its Ledger expense follows" do
    supply = face_wash
    day = @home.today - 2
    keep_rate("JPY", day, "0.20612")
    purchase = Supplies::LogPurchase.call(supply, { quantity: 2, total_price: 169, store: "屈臣氏", purchased_on: day }, user: users(:alex), add_to_ledger: true)

    get edit_household_supply_path(@home, supply)
    assert_select "details[open] [data-controller='paid-currency']" do
      assert_select "select[name='purchase[paid_currency]'] option[selected][value='TWD']"
      assert_select "input[name='purchase[total_price]'][value='169']"
      assert_select "input[name='purchase[purchased_on]'][data-paid-currency-target='date']"
      assert_select "[data-paid-currency-target='panel'][hidden]"
    end

    patch household_supply_path(@home, supply), params: { supply: { name: supply.name },
      purchase: { purchased_on: day, quantity: 2, total_price: 1196, paid_currency: "JPY", paid_by: "cash", home_total: "247", store: "松本清" } }
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 247, "JPY", 1196, "cash", "松本清" ], purchase.reload.values_at(:total_price, :paid_currency, :paid_total, :paid_by, :store)
    assert_equal 247, purchase.record.reload.amount_paid

    get edit_household_supply_path(@home, supply)
    assert_select "select[name='purchase[paid_currency]'] option[selected][value='JPY']"
    assert_select "input[name='purchase[total_price]'][value='1196']", 1, "the price box shows the yen price again"
    assert_select "input[name='purchase[paid_by]'][value='cash'][checked]"
    assert_select "input[name='purchase[home_total]'][value='247']"
    assert_select "[data-paid-currency-target='panel']:not([hidden])"

    patch household_supply_path(@home, supply), params: { supply: { name: supply.name },
      purchase: { purchased_on: day, quantity: 2, total_price: 169, paid_currency: "TWD", store: "屈臣氏" } }
    assert_equal [ 169, nil, nil, nil, nil ], purchase.reload.values_at(:total_price, :paid_currency, :paid_total, :paid_by, :exchange_rate)
    assert_equal 169, purchase.record.reload.amount_paid
    assert_equal 1, supply.purchases.count
  end

  test "bought abroad: a new item's first purchase and an old price take another currency too, at the rate for their own day" do
    day = @home.today - 2
    long_ago = @home.today - 76
    keep_rate("JPY", day, "0.20612")
    keep_rate("JPY", long_ago, "0.20124")

    get new_household_supply_path(@home)
    assert_select "select[name='purchase[paid_currency]'] option[selected][value='TWD']"
    post household_supplies_path(@home), params: { supply: { name: "Face Wash", supply_category_id: category("toiletries").id, unit: "piece", level: 2, lead_days: 3, alert_when_left: 0 },
      purchase: { purchased_on: day, quantity: 2, total_price: 1196, paid_currency: "JPY", paid_by: "card", card_fee_percent: "1.5", card_fee_included: "1", store: "松本清" } }
    supply = @home.supplies.sole
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 250, "JPY", 1196 ], supply.purchases.sole.values_at(:total_price, :paid_currency, :paid_total)

    get new_household_supply_price_path(@home, supply)
    assert_select "form[data-controller~='paid-currency']" do
      assert_select "select[name='supply_price[paid_currency]'] option[selected][value='TWD']"
      assert_select "optgroup[label='用過的'] option[value='JPY']"
      assert_select "input[name='supply_price[purchased_on]'][data-paid-currency-target='date']"
      assert_select "[data-paid-currency-target='panel'][hidden]"
    end
    assert_no_difference -> { supply.counts.count } do
      post household_supply_prices_path(@home, supply), params: { supply_price: { product_name: "Face Wash", store: "松本清", quantity: 1, total_price: 598,
        paid_currency: "JPY", paid_by: "cash", home_total: "120", purchased_on: long_ago } }
    end
    assert_redirected_to household_supply_path(@home, supply)
    assert_equal [ 120, "TWD", "JPY", 598, BigDecimal("0.20124"), "cash" ], supply.prices.sole.values_at(:total_price, :currency, :paid_currency, :paid_total, :exchange_rate, :paid_by)

    get household_supply_path(@home, supply)
    assert_select "details##{dom_id(supply, :price_history)}" do
      assert_select "li", /現金實付 JP¥598/
      assert_select "li", /刷卡實付 JP¥1,196（含手續費）/
    end
    # Where to buy compares in NT$: the old price is the cheaper one
    assert_match "每個 NT$120", response.body
  end

  test "bought abroad: a viewer can't ask for a rate, and a day that hasn't come or isn't a date has none" do
    keep_rate("JPY", @home.today, "0.20612")
    get exchange_rate_household_supplies_path(@home, from: "JPY", on: (@home.today + 1).iso8601)
    assert_equal({ "rate" => nil }, response.parsed_body.to_h)
    get exchange_rate_household_supplies_path(@home, from: "JPY", on: "tomorrow")
    assert_equal({ "rate" => nil }, response.parsed_body.to_h)
    get exchange_rate_household_supplies_path(@home, from: "XXX", on: @home.today.iso8601)
    assert_equal({ "rate" => nil }, response.parsed_body.to_h)
    get exchange_rate_household_supplies_path(@home, from: "JPY", on: @home.today.iso8601)
    assert_equal "0.20612", response.parsed_body["rate"]

    sign_in_as users(:google_only)
    get exchange_rate_household_supplies_path(@home, from: "JPY", on: @home.today.iso8601)
    assert_response :forbidden
  end

  test "stock counted before any purchase: its own −1, then Add details chooses an old price, confirms one, or takes the details with no price" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    lux = "Lux Shampoo 750ml"
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    counted_on = @home.today - 50
    travel_to(counted_on.in_time_zone(@home.time_zone).change(hour: 9)) { Supplies::RecordCount.call(shampoo, 3, user: users(:alex)) }
    Supplies::LogPurchase.call(shampoo.reload, { quantity: 2, total_price: 358, store: "Costco", purchased_on: @home.today, left_before: 3, product_name: lux,
                                                 expires_on: @home.today + 100 }, user: users(:alex))
    details = new_household_supply_stock_details_path(@home, shampoo)

    get household_supply_path(@home, shampoo)
    assert_select "section#forecast_supply_#{shampoo.id} h3 + ul > li:last-child" do
      assert_select "span", /沒有到期日/
      assert_select "a[href=?]", details, text: "補上資料 ›"
      assert_select "form input[name=batch][value=none]"
    end

    post household_supply_counts_path(@home, shampoo), params: { used_one: 1, batch: "none" }, as: :turbo_stream
    assert_match "用掉 1 · 沒有到期日 · 剩 4 瓶", response.body
    assert_equal [ 2, 2 ], shampoo.reload.brands.batches.map(&:left)

    # No old prices from before then: the details to type, the price optional
    shampoo.prices.create!(household: @home, purchased_on: counted_on + 1, quantity: 1, total_price: 189, currency: "TWD")
    get details
    assert_select "h1, h2", /補上資料：Shampoo 2 瓶/
    assert_select "input[name='supply_purchase[purchased_on]'][max=?]", counted_on.iso8601
    assert_select "input[name='supply_purchase[total_price]']:not([required])"
    assert_select "label[data-ledger-box-target=box][hidden]"

    # One: shown to confirm
    sep = shampoo.prices.create!(household: @home, purchased_on: counted_on - 20, quantity: 4, total_price: 716, store: "Costco", product_name: lux, currency: "TWD")
    get details
    assert_select "h1, h2", /這 2 瓶是這次買的嗎？/
    assert_select "a[href=?]", new_household_supply_stock_details_path(@home, shampoo, enter: 1), text: "不是，自己填"
    assert_select "button", /是，儲存/

    # Two or more: chosen from, or None of these
    aug = shampoo.prices.create!(household: @home, purchased_on: counted_on - 40, quantity: 2, total_price: 398, store: "Carrefour", currency: "TWD")
    get details, params: { price_id: aug.id }
    assert_select "h1, h2", /這 2 瓶是從哪裡來的？/
    assert_select "a[aria-current=true][href=?]", new_household_supply_stock_details_path(@home, shampoo, price_id: aug.id)
    assert_select "a[href=?]", new_household_supply_stock_details_path(@home, shampoo, enter: 1), text: /都不是，自己填/
    assert_select "input[name=price_id][value=?]", aug.id.to_s

    post household_supply_stock_details_path(@home, shampoo), params: { price_id: sep.id, supply_purchase: { quantity: 4, expires_on: @home.today + 30 } }
    assert_redirected_to household_supply_path(@home, shampoo)
    follow_redirect!
    assert_select "#notice", /已補上Shampoo 2 瓶的資料。/
    purchase = shampoo.purchases.find_by!(purchased_on: counted_on - 20)
    assert_not SupplyPrice.exists?(sep.id)
    assert_equal [ [ purchase, 2 ], [ shampoo.purchases.find_by!(purchased_on: @home.today), 2 ] ], shampoo.reload.brands.batches.map { [ it.purchase, it.left ] }
    assert_select "a[href=?]", details, 0

    get details
    assert_redirected_to household_supply_path(@home, shampoo)
  end

  test "Add details with no price: saved, and refused when bought after the count" do
    travel_to ActiveSupport::TimeZone[@home.time_zone].now.noon
    shampoo = create_item(name: "Shampoo", unit: "bottle", level: 0, guess_days_per_unit: 30)
    counted_on = @home.today - 50
    travel_to(counted_on.in_time_zone(@home.time_zone).change(hour: 9)) { Supplies::RecordCount.call(shampoo, 3, user: users(:alex)) }
    Supplies::LogPurchase.call(shampoo.reload, { quantity: 2, total_price: 358, purchased_on: @home.today, left_before: 3, expires_on: @home.today + 100 }, user: users(:alex))
    save = household_supply_stock_details_path(@home, shampoo)

    assert_no_difference -> { shampoo.purchases.count } do
      post save, params: { supply_purchase: { purchased_on: counted_on + 1, quantity: 3, total_price: "" } }
    end
    assert_response :unprocessable_content
    assert_select "ul.bg-red-50", /盤點的那天/

    assert_no_difference -> { @home.records.count } do
      post save, params: { add_to_ledger: "1", supply_purchase: { purchased_on: counted_on, quantity: 3, total_price: "", paid_currency: "TWD", store: "" } }
    end
    assert_redirected_to household_supply_path(@home, shampoo)
    assert_nil shampoo.purchases.find_by!(purchased_on: counted_on).total_price
    follow_redirect!
    assert_response :success
  end
end
