# A supply category needs a name in one language, not always Chinese. A category added so far with
# only an English name (typed on an English form, it went in name_zh) moves to name_en.
class SupplyCategoryNamesInEitherLanguage < ActiveRecord::Migration[8.1]
  class Row < ActiveRecord::Base
    self.table_name = "supply_categories"
  end

  CJK = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/

  def up
    change_column_null :supply_categories, :name_zh, true
    Row.where(key: nil, name_en: [ nil, "" ]).find_each do |row|
      next unless row.name_zh.match?(/\p{Latin}/) && !row.name_zh.match?(CJK)
      next if Row.where(household_id: row.household_id).where("LOWER(name_en) = ?", row.name_zh.downcase).exists?

      row.update_columns(name_en: row.name_zh, name_zh: nil)
    end
  end

  def down
    Row.where(name_zh: nil).find_each { it.update_columns(name_zh: it.name_en) }
    change_column_null :supply_categories, :name_zh, false
  end
end
