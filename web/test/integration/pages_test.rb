require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "home page is public" do
    get root_path
    assert_response :success
    assert_select "a[href=?]", privacy_path
  end

  test "privacy policy is public and covers Google user data" do
    get privacy_path
    assert_response :success
    assert_match "Limited Use", response.body
  end
end
