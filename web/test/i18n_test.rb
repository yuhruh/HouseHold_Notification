require "test_helper"

# PRD §17: every string exists in both zh-TW and en
class I18nTest < ActiveSupport::TestCase
  def keys(locale)
    flatten = ->(hash, prefix = nil) { hash.flat_map { |k, v| v.is_a?(Hash) ? flatten.(v, [ prefix, k ].compact.join(".")) : [ [ prefix, k ].compact.join(".") ] } }
    files = [ Rails.root.join("config/locales/#{locale}.yml"), *Dir[Rails.root.join("config/locales/*.#{locale}.yml")] ]
    files.flat_map { |file| flatten.(YAML.load_file(file)[locale.to_s]) }
  end

  test "zh-TW and en define the same keys" do
    en, zh = keys(:en), keys(:"zh-TW")
    assert_empty en - zh, "missing in zh-TW"
    assert_empty zh - en, "missing in en"
  end
end
