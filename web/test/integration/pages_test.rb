require "test_helper"

class PagesTest < ActionDispatch::IntegrationTest
  test "home page is public" do
    get root_path
    assert_response :success
    assert_select "a[href=?]", privacy_path
    assert_select "a[href=?]", guide_path
    assert_select "[data-controller=install] button[hidden]"
  end

  test "the home page has one Install the App card for every phone, hidden in the installed app" do
    get root_path
    assert_select "section.standalone\\:hidden[aria-labelledby=install_heading]" do
      assert_select "h2", /安裝 App/
      assert_select "li.bg-amber-50", /Android/ do
        assert_select "[data-controller=install] button[hidden][data-install-target=button]"
      end
      assert_select "li.bg-sky-50", /iPhone \/ iPad/
    end
  end

  test "privacy policy is public and covers Google user data" do
    get privacy_path
    assert_response :success
    assert_match "Limited Use", response.body
  end
end
