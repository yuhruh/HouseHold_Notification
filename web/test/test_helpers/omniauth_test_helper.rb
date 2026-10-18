module OmniauthTestHelper
  # Walks the real flow in OmniAuth test mode: our handoff endpoint, the request phase, the callback.
  def google_sign_in(uid:, email:, verified: true, name: "Test User", tz: "Asia/Taipei", return_to: nil)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid:, info: { email:, name: }, extra: { raw_info: { email_verified: verified } })
    post google_sign_in_path, params: { tz:, return_to: }.compact
    assert_response :temporary_redirect
    post "/auth/google_oauth2"
    follow_redirect!
  end
end

OmniAuth.config.test_mode = true

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include OmniauthTestHelper
end
