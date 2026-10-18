require "test_helper"

# PRD §17: every string exists in both zh-TW and en
class I18nTest < ActiveSupport::TestCase
  def keys(locale)
    flatten = ->(hash, prefix = nil) { hash.flat_map { |k, v| v.is_a?(Hash) ? flatten.(v, [ prefix, k ].compact.join(".")) : [ [ prefix, k ].compact.join(".") ] } }
    flatten.(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale.to_s])
  end

  test "zh-TW and en define the same keys" do
    en, zh = keys(:en), keys(:"zh-TW")
    assert_empty en - zh, "missing in zh-TW"
    assert_empty zh - en, "missing in en"
  end
end
