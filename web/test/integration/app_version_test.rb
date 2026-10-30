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

  test "every page carries the build, the update card and About This App in your menu; Ledger Settings no longer has the version" do
    sign_in_as users(:alex)
    get household_settings_path(households(:home))
    assert_select "meta[name=app-build][content=?][data-turbo-track=reload]", AppVersion.build
    assert_select "body[data-controller=app-update][data-app-update-build-value=?]", AppVersion.build
    assert_select "[data-app-update-target=card][hidden] a[href=?]", about_path
    assert_select "header details a[href=?]", about_path, text: /#{Regexp.escape(AppVersion.current)}/ do
      assert_select "[data-app-update-target=newBadge][hidden]"
    end
    assert_select "header details summary [data-app-update-target=newBadge][hidden]"
    assert_select "#app-version", count: 0
  end

  test "About This App shows the version, Check For Updates and every version's notes, older ones folded" do
    sign_in_as users(:alex)
    get about_path
    assert_response :success
    assert_select "[data-app-update-target=about]"
    assert_select "#app-version", text: /#{Regexp.escape(AppVersion.current)}/
    assert_select "#app-version button[data-action='app-update#checkNow']"
    assert_select "#whats_new [data-version]", AppVersion.changelog.size
    assert_select "#whats_new > [data-version]", [ AppVersion.changelog.size, 2 ].min
    assert_select "#whats_new [data-version=?] li", AppVersion.current, text: AppVersion.changelog.first["zh-TW"].first
    assert_select "#whats_new [data-new-tag][hidden]", AppVersion.changelog.size
  end

  test "About This App needs you signed in" do
    get about_path
    assert_redirected_to new_session_path
  end
end
