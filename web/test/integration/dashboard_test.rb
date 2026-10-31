require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    water = @home.categories.find_by!(name_zh: "水費")
    @home.records.create!(record_type: "expense", category: water, period: Period.parse(Date.current.year, "1月-2月"),
      amount_required: 580, amount_paid: 580, paid_on: Date.new(Date.current.year, 1, 20))
  end

  test "every member sees the dashboard; a drill-down frame lists the records with the clicked total" do
    sign_in_as users(:google_only) # viewer
    get household_dashboard_path(@home)
    assert_response :success
    assert_select "[data-controller=chart]", 6
    assert_select "h2", text: "帳單期間比較"
    assert_select "a[aria-current=true]", text: "時間軸"
    assert_select "details summary", text: "以表格檢視"
    assert_select "select[name=year] option[value=all]", "全部年度"

    get household_dashboard_path(@home, year: "all")
    assert_response :success
    assert_select "select[name=year] option[selected][value=all]"
    assert_select "p", text: "全部年度已繳"
    assert_select "h2", text: "每年支出（依類型）"

    all_paid = drilldown_household_dashboard_path(@home, mode: "paid", year: "all", currency: "TWD")
    assert_select "a[href=?][data-turbo-frame=drilldown]", all_paid, /全部年度已繳/
    get all_paid
    assert_select "turbo-frame#drilldown td#drilldown-total", "NT$580"
    assert_select "turbo-frame#drilldown h2", /全部年度/

    get household_dashboard_path(@home)
    assert_select "a[href=?][data-turbo-frame=drilldown]", drilldown_household_dashboard_path(@home, mode: "paid", year: Date.current.year, currency: "TWD"), /已繳/

    get drilldown_household_dashboard_path(@home, mode: "period", year: Date.current.year, currency: "TWD", month: 2)
    assert_response :success
    assert_select "turbo-frame#drilldown td#drilldown-total", "NT$290"
    assert_select "turbo-frame#drilldown a", "水費"
    # On a phone a card per record, with the total under them
    assert_select "turbo-frame#drilldown ul.sm\\:hidden li a", "水費"
    assert_select "turbo-frame#drilldown p.sm\\:hidden", /NT\$290/
  end

  test "other households' records never appear" do
    sign_in_as users(:newbie)
    get household_dashboard_path(@home)
    assert_response :not_found
  end
end
