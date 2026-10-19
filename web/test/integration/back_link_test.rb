require "test_helper"

class BackLinkTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alex) }

  test "signed-in pages have a Back link that falls back to the household home" do
    home = households(:home)
    [ household_records_path(home), household_settings_path(home), account_path, guide_path ].each do |path|
      get path
      assert_select "a[data-controller=back][href=?]", household_path(home), { count: 1 }, path
    end
  end

  test "the household home itself has none" do
    get household_path(households(:home))
    assert_select "a[data-controller=back]", count: 0
  end
end
