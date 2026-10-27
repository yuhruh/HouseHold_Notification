require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
  end

  def bill(due_on, paid: false)
    @home.records.create!(record_type: "expense", category: @home.categories.find_by!(name_zh: "水費"), period: Period.parse(2026, "1月-2月"),
                          due_on:, amount_required: 580, **(paid ? { amount_paid: 580, paid_on: Date.current } : {}))
  end

  test "computer: Bills and Expense Analysis in the bar, Bills tinted on both its views, New Record only in the bar" do
    sign_in_as users(:alex)
    get household_records_path(@home)

    assert_select "header nav details summary", text: /帳單/, count: 0
    assert_select "header nav > a.bg-blue-100[aria-current=page][href=?]", household_pending_path(@home), text: /帳單/
    assert_select "header nav > a[href=?]", household_dashboard_path(@home), text: /支出分析/
    assert_select "header a.btn-new[href=?]", new_household_record_path(@home), 1
    get household_pending_path(@home)
    assert_select "header nav > a.bg-blue-100[href=?]", household_pending_path(@home)
    get household_dashboard_path(@home)
    assert_select "header nav > a.bg-blue-100[href=?]", household_dashboard_path(@home)
    assert_select "header nav > a.bg-blue-100[href=?]", household_pending_path(@home), 0
  end

  test "Bills is one page: To Pay and All switched at the top, To Pay with its count" do
    bill(Date.current - 3)
    bill(Date.current + 5)
    bill(Date.current - 1, paid: true)
    sign_in_as users(:alex)
    get household_pending_path(@home)

    assert_select "h1", /帳單/
    assert_select "main nav[aria-label='顯示']" do
      assert_select "a[aria-current=page][href=?]", household_pending_path(@home), text: /待繳\s*2/
      assert_select "a[href=?]", household_records_path(@home), text: "全部"
    end
    assert_select "title", /待繳帳單/
    get household_records_path(@home)
    assert_select "main nav[aria-label='顯示'] a[aria-current=page][href=?]", household_records_path(@home)
    assert_select "main nav[aria-label='顯示'] a[href=?]", household_pending_path(@home), text: /待繳\s*2/
    assert_select "title", /所有帳單/
  end

  test "All: Export CSV of what the filters show and Import sit above the list, not in the menus" do
    bill(Date.current + 5)
    sign_in_as users(:alex)
    get household_records_path(@home, type: "expense")

    assert_select "main a[href=?]", household_records_path(@home, type: "expense", format: :csv), /匯出這 1 筆/
    assert_select "main a[href=?]", new_household_import_path(@home), /匯入 CSV/
    assert_select "header a[href=?]", household_records_path(@home, type: "expense", format: :csv), 0
    assert_select "header a[href=?]", new_household_import_path(@home), 0
    get household_pending_path(@home)
    assert_select "main a[href*='records.csv']", 0, "To Pay has nothing to export"
  end

  test "All: search and filters are folded behind the Filters button; the ones in use show as tags" do
    bill(Date.current + 5)
    sign_in_as users(:alex)
    get household_records_path(@home)
    assert_select "main details:not([open]) summary", /篩選/
    assert_select "main details form input[type=search][name=q]"
    assert_select "main ul[aria-label] li", 0

    get household_records_path(@home, type: "expense", q: "水")
    assert_select "main details summary span[aria-label=?]", "已套用 2 個篩選", text: "2"
    assert_select "main ul[aria-label='已套用 2 個篩選']" do
      assert_select "li", text: /支出/
      assert_select "li", text: /搜尋：水/
      assert_select "a[aria-label='移除 支出'][href=?]", household_records_path(@home, q: "水")
      assert_select "a[href=?]", household_records_path(@home), text: "清除"
    end
  end

  test "phone: the tab bar has Bills, Analysis and New Record; the header menus leave them out" do
    sign_in_as users(:alex)
    get household_records_path(@home)

    assert_select "nav[aria-label='主要頁面']" do
      assert_select "a[aria-current=page][href=?]", household_pending_path(@home), text: /帳單/
      assert_select "a[href=?]", household_dashboard_path(@home)
      assert_select "a[href=?] .btn-new", new_household_record_path(@home)
    end
    assert_select "header details a[href=?]", household_pending_path(@home), 0
  end

  test "the red count is the unpaid bills due today or earlier" do
    bill(Date.current - 3)
    bill(Date.current)
    bill(Date.current + 5)
    bill(Date.current - 1, paid: true)
    sign_in_as users(:alex)
    get household_path(@home)

    assert_select "header nav > a span[aria-label=?]", "2 筆帳單到期或逾期", text: "2"
    assert_select "nav[aria-label='主要頁面'] span[aria-label=?]", "2 筆帳單到期或逾期", text: "2"
  end

  test "a viewer gets no New Record or Import, and can still export" do
    bill(Date.current + 5)
    sign_in_as users(:google_only)
    get household_records_path(@home)

    assert_select "a[href=?]", new_household_record_path(@home), 0
    assert_select "nav[aria-label='主要頁面'] a", 2
    assert_select "main a[href=?]", household_records_path(@home, format: :csv), 1
    assert_select "a[href=?]", new_household_import_path(@home), 0
  end

  test "your menu: My Account, theme and language switches, Getting Started and Sign Out; tinted on their pages" do
    sign_in_as users(:alex)
    get household_members_path(@home)
    assert_select "header details summary[aria-label=?]", "你的選單"
    assert_select "header details a[href=?]", account_path, /我的帳戶/
    assert_select "header details form[action=?] button", theme_path, 3
    assert_select "header details form[action=?] button[aria-current=true]", locale_path, /中文/
    assert_select "header details a[href=?]", guide_path
    assert_select "header details form[action=?] button", session_path, /登出/
    assert_select "header details a.bg-blue-50[href=?]", household_settings_path(@home), 1, "Settings covers the pages it opens"
    assert_select "header details a.bg-blue-50[href=?]", account_path, 0

    get account_path
    assert_select "header details a.bg-blue-50[href=?]", account_path
    get guide_path
    assert_select "header details a.bg-blue-50[href=?]", guide_path
    assert_select "header details a.bg-blue-50[href=?]", household_settings_path(@home), 0
    assert_select "header dialog", 0, "no hamburger menu when signed in"
  end
end
