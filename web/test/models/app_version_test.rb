require "test_helper"

class AppVersionTest < ActiveSupport::TestCase
  test "the changelog is newest first, every entry dated and in both languages" do
    versions = AppVersion.changelog.map { |e| e["version"] }
    assert_equal versions.sort_by { Gem::Version.new(it) }.reverse, versions
    assert_equal versions.uniq, versions
    AppVersion.changelog.each do |entry|
      assert_match(/\A\d+\.\d+\.\d+\z/, entry["version"])
      assert_kind_of Date, entry["date"]
      assert entry["en"].present? && entry["zh-TW"].present?, entry["version"]
      assert_equal entry["en"].size, entry["zh-TW"].size, entry["version"]
    end
  end

  # A second date:, en: or zh-TW: under one version silently replaces the first (YAML keeps the last), which
  # is what a lost "- version:" line does: that entry's notes vanish and the one above shows the wrong ones
  test "no changelog entry has the same key twice" do
    entries = Psych.parse_file(Rails.root.join("config/changelog.yml")).root.children
    assert_equal AppVersion.changelog.size, entries.size
    entries.each do |entry|
      keys = entry.children.each_slice(2).map { |key, _| key.value }
      assert_equal %w[version date en zh-TW], keys
    end
  end

  test "since lists the newer entries; the build falls back to the version" do
    assert_equal AppVersion.changelog.first["version"], AppVersion.current
    assert_equal [], AppVersion.since(AppVersion.current)
    assert_equal AppVersion.changelog.size - 1, AppVersion.since(AppVersion.changelog.last["version"]).size
    assert_equal AppVersion.current, AppVersion.build unless ENV["RAILWAY_GIT_COMMIT_SHA"]
  end

  test "a date version saved before the 1.0.x numbers gets the entries after that date" do
    newest = AppVersion.entries.first
    assert_equal [], AppVersion.since(newest.date.strftime("%Y.%m.%d"))
    same_day = AppVersion.entries.select { it.date == newest.date }.map(&:version) # releases can share a day
    assert_equal same_day, AppVersion.since((newest.date - 1).strftime("%Y.%m.%d.2")).map(&:version)
    assert_equal [], AppVersion.since("junk")
  end
end
