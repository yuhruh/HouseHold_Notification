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

  # YAML keeps only the last of a repeated key, so a second `errors:` or `form:` block in the same
  # place silently drops the first one's wording
  test "no locale file has the same key twice in one place" do
    Rails.root.glob("config/locales/*.yml").each do |file|
      repeated = []
      walk = ->(node, path) do
        if node.is_a?(Psych::Nodes::Mapping)
          pairs = node.children.each_slice(2).to_a
          pairs.map { |key, _| key.value }.tally.each { |key, times| repeated << (path + [ key ]).join(".") if times > 1 }
          pairs.each { |key, value| walk.(value, path + [ key.value ]) }
        else
          Array(node.children).each { walk.(it, path) }
        end
      end
      walk.(Psych.parse_file(file), [])
      assert_empty repeated, "#{file.basename} repeats a key"
    end
  end
end
