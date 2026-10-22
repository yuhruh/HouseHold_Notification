require "test_helper"

class AppVersionTest < ActiveSupport::TestCase
  test "the changelog is newest first, every entry dated and in both languages" do
    versions = AppVersion.changelog.map { |e| e["version"] }
    assert_equal versions.sort.reverse, versions
    assert_equal versions.uniq, versions
    AppVersion.changelog.each do |entry|
      assert_match(/\A\d{4}\.\d{2}\.\d{2}(\.\d+)?\z/, entry["version"])
      assert_kind_of Date, entry["date"]
      assert entry["en"].present? && entry["zh-TW"].present?, entry["version"]
      assert_equal entry["en"].size, entry["zh-TW"].size, entry["version"]
    end
  end

  test "since lists the newer entries; the build falls back to the version" do
    assert_equal AppVersion.changelog.first["version"], AppVersion.current
    assert_equal [], AppVersion.since(AppVersion.current)
    assert_equal AppVersion.changelog.size - 1, AppVersion.since(AppVersion.changelog.last["version"]).size
    assert_equal AppVersion.current, AppVersion.build unless ENV["RAILWAY_GIT_COMMIT_SHA"]
  end
end
