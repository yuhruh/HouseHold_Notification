require "test_helper"

class DriveBackups::OauthTest < ActiveSupport::TestCase
  # Runs the real Signet client against Google's response, sent by Faraday's test adapter
  def exchange(status: 200, **body)
    connection = Faraday.new do |f|
      f.adapter(:test) { |stub| stub.post("/token") { [ status, { "Content-Type" => "application/json" }, body.to_json ] } }
    end
    with_stub(Faraday, :default_connection, connection) { DriveBackups::Oauth.exchange(code: "c", redirect_uri: "https://x.test/cb") }
  end

  test "returns the refresh token when Drive was granted" do
    assert_equal "r", exchange(access_token: "a", refresh_token: "r", expires_in: 3600, scope: DriveBackups::Oauth::SCOPE)
  end

  test "refuses when Drive was unticked, there's no refresh token, or Google says no" do
    assert_raises(DriveBackups::Oauth::Denied) { exchange(access_token: "a", refresh_token: "r", scope: "openid") }
    assert_raises(DriveBackups::Oauth::Denied) { exchange(access_token: "a", scope: DriveBackups::Oauth::SCOPE) }
    assert_raises(DriveBackups::Oauth::Denied) { exchange(status: 401, error: "invalid_client") }
  end
end
