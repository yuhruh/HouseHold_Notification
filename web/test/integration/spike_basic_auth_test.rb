require "test_helper"

class SpikeBasicAuthTest < ActionDispatch::IntegrationTest
  # Made-up credentials, only for these tests
  USER = "spike-test-user"
  PASSWORD = "made-up-spike-password-4821"

  setup do
    @saved_env = %w[SPIKE_USER SPIKE_PASSWORD].to_h { |key| [ key, ENV[key] ] }
    ENV["SPIKE_USER"] = USER
    ENV["SPIKE_PASSWORD"] = PASSWORD
  end

  teardown { @saved_env.each { |key, value| ENV[key] = value } }

  test "the right password gets in" do
    get spike_charts_path, headers: right_password
    assert_response :success
  end

  test "requests without credentials are asked for them and not counted" do
    20.times do
      get spike_charts_path
      assert_response :unauthorized
      assert_includes response.headers["WWW-Authenticate"], %(realm="spike")
    end

    get spike_charts_path, headers: right_password
    assert_response :success
  end

  test "after 10 wrong passwords an IP is turned away, even with the right one" do
    10.times do
      get spike_charts_path, headers: wrong_password
      assert_response :unauthorized
    end

    get spike_charts_path, headers: right_password
    assert_response :too_many_requests
    get spike_charts_path, headers: wrong_password
    assert_response :too_many_requests
  end

  test "the IP gets back in once the window ends" do
    10.times { get spike_charts_path, headers: wrong_password }

    travel Spike::BaseController::GUESS_WINDOW + 1.second
    get spike_charts_path, headers: right_password
    assert_response :success
  end

  test "right passwords do not use up the allowance" do
    9.times { get spike_charts_path, headers: wrong_password }
    20.times do
      get spike_charts_path, headers: right_password
      assert_response :success
    end

    get spike_charts_path, headers: wrong_password
    assert_response :unauthorized
    get spike_charts_path, headers: right_password
    assert_response :too_many_requests
  end

  test "wrong passwords from other IPs do not lock out the right one" do
    30.times do |i|
      10.times { get spike_charts_path, headers: wrong_password, env: { "REMOTE_ADDR" => "198.51.100.#{i + 1}" } }
    end
    get spike_charts_path, headers: right_password, env: { "REMOTE_ADDR" => "198.51.100.1" }
    assert_response :too_many_requests

    get spike_charts_path, headers: right_password, env: { "REMOTE_ADDR" => "203.0.113.9" }
    assert_response :success
  end

  test "when the cache cannot count, the password check still decides" do
    saved_store = Spike::BaseController.cache_store
    Spike::BaseController.cache_store = :null_store # increment returns nil, like a Solid Cache failsafe

    15.times do
      get spike_charts_path, headers: wrong_password
      assert_response :unauthorized
    end
    get spike_charts_path, headers: right_password
    assert_response :success
  ensure
    Spike::BaseController.cache_store = saved_store
  end

  private
    def right_password = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(USER, PASSWORD) }
    def wrong_password = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(USER, "guess") }
end
