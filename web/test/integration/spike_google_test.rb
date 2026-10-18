require "test_helper"

class SpikeGoogleTest < ActionDispatch::IntegrationTest
  test "page offers sign-in and re-auth" do
    get spike_google_path
    assert_response :success
    assert_select "form[action=?]", spike_google_start_path(mode: "reauth")
  end

  test "re-authenticate sends Google prompt=login and max_age=0" do
    post spike_google_start_path(mode: "reauth")
    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal "login", query["prompt"]
    assert_equal "0", query["max_age"]
    assert_equal "http://www.example.com/auth/google_oauth2/callback", query["redirect_uri"]
  end

  test "sign in lets the user pick an account" do
    post spike_google_start_path(mode: "signin")
    query = Rack::Utils.parse_query(URI(response.location).query)
    assert_equal "select_account", query["prompt"]
    assert_nil query["max_age"]
  end

  test "callback with a wrong state is rejected before any token exchange" do
    post spike_google_start_path(mode: "signin")
    get "/auth/google_oauth2/callback", params: { state: "forged", code: "x" }
    assert_redirected_to spike_google_path
    assert_equal "State mismatch; start again", flash[:alert]
  end

  test "fresh_auth? needs an auth_time at or after the request" do
    requested_at = Time.current.to_i
    assert Spike::GoogleOidc.fresh_auth?({ "auth_time" => requested_at + 5 }, requested_at)
    assert_not Spike::GoogleOidc.fresh_auth?({ "auth_time" => requested_at - 600 }, requested_at)
    assert_not Spike::GoogleOidc.fresh_auth?({}, requested_at)
  end
end
