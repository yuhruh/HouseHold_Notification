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

  test "the household home itself has none" do
    get household_path(households(:home))
    assert_select "a", text: "‹ 回到首頁", count: 0
  end
end
