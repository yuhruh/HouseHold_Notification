require "test_helper"

class ThemeSwitchTest < ActionDispatch::IntegrationTest
  test "light by default" do
    get new_session_path
    assert_select "html[data-theme=light]"
    assert_select "button[aria-current=true]", /Light|淺色/
  end

  test "the choice is kept in a cookie and goes back" do
    sign_in_as users(:alex)
    patch theme_path, params: { theme: "dark" }, headers: { "Referer" => "http://www.example.com/account" }
    assert_redirected_to "http://www.example.com/account"
    follow_redirect!
    assert_select "html[data-theme=dark]"
    assert_select "button[aria-current=true]", /Dark|深色/

    patch theme_path, params: { theme: "system" }
    get account_path
    assert_select "html[data-theme=system]"
  end

  test "an unknown theme is ignored" do
    patch theme_path, params: { theme: "neon" }
    assert_redirected_to root_path
    get new_session_path
    assert_select "html[data-theme=light]"
  end
end
