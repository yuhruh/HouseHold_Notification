require "test_helper"

class LocaleSwitchTest < ActionDispatch::IntegrationTest
  test "signed in: the header switch saves the user's language and goes back" do
    sign_in_as users(:alex)
    users(:alex).update!(locale: "zh-TW")
    patch locale_path, params: { locale: "en" }, headers: { "Referer" => "http://www.example.com/account" }
    assert_redirected_to "http://www.example.com/account"
    assert_equal "en", users(:alex).reload.locale
    follow_redirect!
    assert_select "button[aria-current=true]", /English/
  end

  test "signed out: the choice is kept in a cookie" do
    get new_session_path, headers: { "Accept-Language" => "zh-TW" }
    assert_select "button[aria-current=true]", /繁體中文/
    patch locale_path, params: { locale: "en" }
    get new_session_path, headers: { "Accept-Language" => "zh-TW" }
    assert_select "button[aria-current=true]", /English/
  end

  test "an unknown language is ignored" do
    sign_in_as users(:alex)
    users(:alex).update!(locale: "zh-TW")
    patch locale_path, params: { locale: "fr" }
    assert_redirected_to root_path
    assert_equal "zh-TW", users(:alex).reload.locale
  end

  test "it never redirects to another site" do
    patch locale_path, params: { locale: "en" }, headers: { "Referer" => "https://evil.example/x" }
    assert_redirected_to root_path
  end
end
