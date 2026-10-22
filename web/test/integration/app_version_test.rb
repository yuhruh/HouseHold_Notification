require "test_helper"

class AppVersionFlowTest < ActionDispatch::IntegrationTest
  test "the version endpoint gives the build and what's new since a version, never cached" do
    oldest = AppVersion.changelog.last["version"]
    get app_version_path(since: oldest), headers: { "Accept-Language" => "en" }
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    body = response.parsed_body
    assert_equal [ AppVersion.current, AppVersion.build ], body.values_at("version", "build")
    assert_equal AppVersion.since(oldest).map(&:version), body["notes"].map { |n| n["version"] }
    assert_equal AppVersion.changelog.first["en"], body["notes"].first["notes"]

    get app_version_path(since: AppVersion.current)
    assert_empty response.parsed_body["notes"]
  end

  test "every page carries the build for the update check; Settings shows the version and what's new" do
    sign_in_as users(:alex)
    get household_settings_path(households(:home))
    assert_select "meta[name=app-build][content=?][data-turbo-track=reload]", AppVersion.build
    assert_select "body[data-controller=app-update][data-app-update-build-value=?]", AppVersion.build
    assert_select "#app-version button[data-action='app-update#checkNow']"
    assert_select "#app-version", text: /#{Regexp.escape(AppVersion.current)}/
    assert_select "#app-version li", text: AppVersion.changelog.first["zh-TW"].first
  end
end
