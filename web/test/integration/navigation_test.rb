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

  test "computer: Pending, Records and Expense Analysis in the Bills menu, New Record only in the bar" do
    sign_in_as users(:alex)
    get household_records_path(@home)

    assert_select "header nav details" do
      assert_select "summary", /帳單/
      assert_select "a[href=?]", household_pending_path(@home)
      assert_select "a[href=?][aria-current=page]", household_records_path(@home)
      assert_select "a[href=?]", household_dashboard_path(@home)
      assert_select "a[href=?]", new_household_record_path(@home), 0
    end
    assert_select "header nav > a.btn-new[href=?]", new_household_record_path(@home), 1
  end

  test "phone: the tab bar has the same three pages and New Record; the hamburger menu leaves them out" do
    sign_in_as users(:alex)
    get household_dashboard_path(@home)

    assert_select "nav[aria-label='帳單']" do
      assert_select "a[href=?]", household_pending_path(@home)
      assert_select "a[href=?]", household_records_path(@home)
      assert_select "a[href=?][aria-current=page]", household_dashboard_path(@home)
      assert_select "a[href=?] .btn-new", new_household_record_path(@home)
    end
    assert_select "header dialog a[href=?]", household_pending_path(@home), 0
  end

  test "the red count is the unpaid bills due today or earlier" do
    bill(Date.current - 3)
    bill(Date.current)
    bill(Date.current + 5)
    bill(Date.current - 1, paid: true)
    sign_in_as users(:alex)
    get household_path(@home)

    assert_select "header nav details summary span[aria-label=?]", "2 筆帳單到期或逾期", text: "2"
    assert_select "nav[aria-label='帳單'] span[aria-label=?]", "2 筆帳單到期或逾期", text: "2"
  end

  test "a viewer gets no New Record button" do
    sign_in_as users(:google_only)
    get household_records_path(@home)

    assert_select "a[href=?]", new_household_record_path(@home), 0
    assert_select "nav[aria-label='帳單'] a", 3
  end
end
