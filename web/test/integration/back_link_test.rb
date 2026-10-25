require "test_helper"

class BackLinkTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alex) }

  # A plain link (no browser-history script), so it never steps back into a form already sent
  test "signed-in pages have a Back to Dashboard link to the household home" do
    home = households(:home)
    [ household_records_path(home), household_settings_path(home), account_path ].each do |path|
      get path
      assert_select "a[href=?]:not([data-controller])", household_path(home), { count: 1, text: "‹ 回到首頁" }, path
    end
  end

  test "Records opened from Past Records → See All lead back to that record, through filtering and paging" do
    home = households(:home)
    Categories::Seed.call(home)
    record = home.records.create!(record_type: "expense", category: home.categories.find_by!(name_zh: "水費"), period: Period.parse(2026, "1月-2月"))
    get household_records_path(home, category_id: record.category_id, from: record.id)
    assert_select "a[href=?]", household_record_path(home, record), text: "‹ 回到上一頁"
    assert_select "input[type=hidden][name=from][value=?]", record.id.to_s
    get household_records_path(home, from: 0)
    assert_select "a[href=?]", household_path(home), text: "‹ 回到首頁"
  end

  test "the household home itself has none" do
    get household_path(households(:home))
    assert_select "a", text: "‹ 回到首頁", count: 0
  end
end
