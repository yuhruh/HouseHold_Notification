require "test_helper"

class GoogleSignInTest < ActionDispatch::IntegrationTest
  teardown { OmniAuth.config.mock_auth[:google_oauth2] = nil }

  test "rule 1: a known identity signs in to its user" do
    google_sign_in(uid: "google-uid-sam", email: "sam@example.com")
    assert_redirected_to root_path
    assert_equal users(:google_only), Session.last.user
  end

  test "rule 2: a signed-in user connecting Google links it to themselves" do
    sign_in_as users(:alex)
    assert_difference("users(:alex).identities.count") do
      google_sign_in(uid: "new-uid", email: "alex.other@gmail.com", verified: false)
    end
    assert_equal I18n.t("omniauth_callbacks.create.linked"), flash[:notice]
  end

  test "rule 3: a verified Google email matching a verified account links and signs in" do
    assert_no_difference("User.count") { google_sign_in(uid: "alex-uid", email: "alex@example.com") }
    assert_equal users(:alex), Identity.find_by!(uid: "alex-uid").user
    assert_equal users(:alex), Session.last.user
  end

  test "rule 4: an unverified Google email is refused" do
    assert_no_difference(%w[User.count Identity.count]) { google_sign_in(uid: "u", email: "x@example.com", verified: false) }
    assert_redirected_to new_session_path
    assert_equal I18n.t("omniauth_callbacks.create.unverified_email"), flash[:alert]
  end

  test "rule 5: no match creates a verified user with the handoff's time zone" do
    google_sign_in(uid: "fresh", email: "fresh@example.com", name: "Fresh", tz: "America/New_York")
    user = User.find_by!(email_address: "fresh@example.com")
    assert user.email_confirmed_at
    assert_equal "America/New_York", user.time_zone
    assert_equal "Fresh", user.display_name
  end

  test "an email held only as someone's unconfirmed_email gives a new verified user, and the squatter can't confirm" do
    squatter = User.create!(unconfirmed_email: "owner@example.com", password: "password123")
    google_sign_in(uid: "owner-uid", email: "owner@example.com")
    assert User.exists?(email_address: "owner@example.com")
    assert_not squatter.confirm_email!
  end

  test "return_to survives the round trip, but only as an internal path" do
    google_sign_in(uid: "google-uid-sam", email: "sam@example.com", return_to: "/privacy")
    assert_redirected_to "/privacy"
    delete session_path

    google_sign_in(uid: "google-uid-sam", email: "sam@example.com", return_to: "https://evil.example/x")
    assert_redirected_to root_path
  end

  test "a callback without a handoff is refused" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "u", info: { email: "a@example.com" })
    post "/auth/google_oauth2"
    follow_redirect!
    assert_redirected_to new_session_path
    assert_equal I18n.t("omniauth_callbacks.create.expired"), flash[:alert]
  end

  test "GET /auth/google_oauth2 is rejected" do
    get "/auth/google_oauth2"
    assert_response :not_found
  end
end

class GoogleSignInForgeryTest < ActionDispatch::IntegrationTest
  setup do
    @forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "google-uid-sam", info: { email: "sam@example.com" }, extra: { raw_info: { email_verified: true } })
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "the button's token is accepted by both the handoff and the OmniAuth request phase" do
    get new_session_path
    token = css_select("form[action='#{google_sign_in_path}'] input[name=authenticity_token]").first["value"]

    post google_sign_in_path, params: { authenticity_token: token, tz: "Asia/Taipei" }
    assert_response :temporary_redirect
    post "/auth/google_oauth2", params: { authenticity_token: token, tz: "Asia/Taipei" }
    assert_redirected_to "/auth/google_oauth2/callback"
  end

  test "the request phase refuses a missing token" do
    post "/auth/google_oauth2"
    assert_response :unprocessable_content
  end
end
