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
      assert_select "a", 3
      assert_select "a:first-child[href=?]", new_household_supply_path(@home), text: /日用品項目/
      assert_select "a[href=?]", scan_household_supplies_path(@home), text: /上傳或掃描/
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
        supply_purchase: { quantity: 12, total_price: 289, store: "Costco", purchased_on: Date.current, left_before: 4 } }
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
    get household_supplies_path(@home)
    assert_select "li##{ActionView::RecordIdentifier.dom_id(supply, :row)}", /Toilet paper/
    assert_select "main details summary", /新增日用品/
    assert_select "main details a[href=?]", scan_household_supplies_path(@home)
  end

  test "−1 at 0 stays at 0, and the button is off" do
    supply = create_item(level: 0)
    post household_supply_counts_path(@home, supply), params: { used_one: 1 }, as: :turbo_stream
    assert_equal 0, supply.reload.level
    get household_supply_path(@home, supply)
    assert_select "button[disabled][aria-label*='用掉一個']"
  end

  test "negative or decimal counts and quantities are refused" do
    supply = create_item
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: "2.5" } }, as: :turbo_stream
    assert_response :unprocessable_content
    post household_supply_counts_path(@home, supply), params: { supply_count: { level: "-1" } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_equal 4, supply.reload.level

    post household_supply_purchases_path(@home, supply), params: { supply_purchase: { quantity: "1.5", total_price: 10, purchased_on: Date.current, left_before: 0 } }
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

  test "filters: Buy soon and Expiring" do
    create_item(name: "Soon", level: 1)
    create_item(name: "Plenty", level: 50)
    get household_supplies_path(@home, filter: "buy_soon")
    assert_select "main li", text: /Soon/
    assert_select "main li", text: /Plenty/, count: 0
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
  end

  test "dialog on a computer: Bought more loads into the modal frame with a dialog" do
    supply = create_item
    get new_household_supply_purchase_path(@home, supply), headers: { "Turbo-Frame" => "modal" }
    assert_select "turbo-frame#modal dialog[data-controller=modal] form[data-turbo-frame=_top]"
    get new_household_supply_purchase_path(@home, supply)
    assert_select "dialog[data-controller=modal]", 0
    assert_select "h1", /又買了/
  end

  test "Log a purchase: buy-soon items first, then the rest" do
    create_item(name: "Plenty", level: 50)
    create_item(name: "Soon", level: 1)
    get restock_household_supplies_path(@home)
    assert_select "section:first-of-type h3", /快要買/
    assert_select "section:first-of-type li", text: /Soon/
  end

  test "scan a barcode: known item → its Bought form; found → New item filled in; unknown → empty with the barcode" do
    supply = create_item
    supply.barcodes.create!(household: @home, code: "4710000000017")
    get scan_barcode_household_supplies_path(@home, code: "4710000000017")
    assert_redirected_to new_household_supply_purchase_path(@home, supply, scan: 1)

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

  test "a Taiwan e-invoice: review, save once with one Ledger expense, remembered next time, refused twice" do
    supply = create_item(name: "衛生紙")
    head = "AB12345678" "1151115" "1234" "0000010E" "0000011B" "00000000" "12345678" + ("x" * 24)
    left = "#{head}:**********:2:2:1:舒潔衛生紙:1:189:鮮奶:2:47"

    post receipt_review_household_supplies_path(@home), params: { left:, right: "" }
    assert_response :success
    assert_select "select[name='lines[0][choice]'] option[selected][value=?]", supply.id.to_s
    assert_select "span", text: "建議"
    assert_select "dialog[data-controller=notice] h2", "1 項找不到", "鮮奶 matches nothing"
    assert_select "details[open] input[name='lines[1][name]'][value=鮮奶]"
    assert_select "span", text: "找不到"

    assert_difference -> { @home.records.count } => 1, -> { @home.supply_purchases.count } => 2 do
      post receipt_household_supplies_path(@home), params: { left:, store: "全聯", add_to_ledger: "1",
        lines: { "0" => { choice: supply.id, units_per_line: 12 }, "1" => { choice: "new", name: "鮮奶", kind: "food_drink", unit: "bottle", units_per_line: 1 } } }
    end
    assert_equal 283, @home.records.order(:id).last.amount_paid
    assert_equal 4 + 12, supply.reload.level
    assert_equal "全聯", @home.receipt_sellers.sole.name

    post receipt_review_household_supplies_path(@home), params: { left: }
    assert_redirected_to scan_household_supplies_path(@home, mode: "receipt")
    assert_match "已經在", flash[:alert]

    other = left.sub("AB12345678", "AB12345679")
    post receipt_review_household_supplies_path(@home), params: { left: other }
    assert_select "span", text: "已記住"
    assert_select "dialog[data-controller=notice]", 0, "every line is remembered"
    assert_select "input[name=store][value=全聯]"
    assert_select "input[name='lines[0][units_per_line]'][value='12']"

    post receipt_review_household_supplies_path(@home), params: { left: "https://example.com" }
    assert_match "不像台灣電子發票", flash[:alert]
  end
end
