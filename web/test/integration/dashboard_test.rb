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
    assert_select "[data-controller=chart]", 5
    assert_select "details summary", text: "以表格檢視"

    get drilldown_household_dashboard_path(@home, mode: "period", year: Date.current.year, currency: "TWD", month: 2)
    assert_response :success
    assert_select "turbo-frame#drilldown td#drilldown-total", "NT$290"
    assert_select "turbo-frame#drilldown a", "水費"
  end

  test "other households' records never appear" do
    sign_in_as users(:newbie)
    get household_dashboard_path(@home)
    assert_response :not_found
  end
end
