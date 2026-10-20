require "test_helper"

class ThemeSwitchTest < ActionDispatch::IntegrationTest
  test "light by default, with a toggle to each theme" do
    get new_session_path
    assert_select "html[data-theme=light]"
    # CSS shows the one to switch to (Dark on a light page); a full reload (not Turbo), so the new
    # data-theme on <html> takes effect
    assert_select "form.dark\\:hidden[action=\"#{theme_path}\"][data-turbo=false] input[name=theme][value=dark]"
    assert_select "form.dark\\:block[action=\"#{theme_path}\"][data-turbo=false] input[name=theme][value=light]"
  end

  test "the choice is kept in a cookie and goes back" do
    sign_in_as users(:alex)
    patch theme_path, params: { theme: "dark" }, headers: { "Referer" => "http://www.example.com/account" }
    assert_redirected_to "http://www.example.com/account"
    follow_redirect!
    assert_select "html[data-theme=dark]"

    patch theme_path, params: { theme: "light" }
    get account_path
    assert_select "html[data-theme=light]"
  end

  test "My account offers Device setting too, and shows this device's choice" do
    sign_in_as users(:alex)
    get account_path
    assert_select "form[action=\"#{theme_path}\"][data-turbo=false] select[name=theme] option", 3
    assert_select "select[name=theme] option[selected][value=light]"

    patch theme_path, params: { theme: "system" }, headers: { "Referer" => "http://www.example.com/account" }
    assert_redirected_to "http://www.example.com/account"
    follow_redirect!
    assert_select "html[data-theme=system]"
    assert_select "select[name=theme] option[selected][value=system]"
  end

  test "an unknown theme is ignored" do
    patch theme_path, params: { theme: "neon" }
    assert_redirected_to root_path
    get new_session_path
    assert_select "html[data-theme=light]"
  end
end
