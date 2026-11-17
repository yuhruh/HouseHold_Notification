# A ledger's own supply categories (Settings › Categories › Supplies). Each ledger starts with six
# (DEFAULTS); owners and co-owners add more, from the item form too. `key` marks a starting one, so
# what a barcode lookup guesses ("kitchen") still finds it after a rename. "Other" always stays, for
# an item without a category. perishable: expiry alerts a week ahead instead of a month.
# A name in one language is enough (name_zh or name_en); whoever reads the other language sees it
# until theirs is added.
class SupplyCategory < ApplicationRecord
  DEFAULTS = { "toiletries" => %w[盥洗用品 Toiletries], "cleaning" => %w[清潔用品 Cleaning], "kitchen" => %w[廚房用品 Kitchen],
               "food_drink" => [ "食品飲料", "Food & drink" ], "health" => %w[保健醫療 Health], "other" => %w[其他 Other] }.freeze
  KEYS = DEFAULTS.keys.freeze
  PERISHABLE = %w[food_drink health].freeze
  FALLBACK = "other".freeze

  belongs_to :household
  has_many :supplies, dependent: :restrict_with_error

  normalizes :name_zh, :name_en, with: ->(name) { name.to_s.squish.presence }

  validates :name_zh, :name_en, length: { maximum: 40 }
  validate { errors.add(:base, :name_missing) if name_zh.blank? && name_en.blank? }
  validate :names_not_taken, if: -> { name_zh_changed? || name_en_changed? }
  validates :key, inclusion: { in: KEYS }, allow_nil: true

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  # The six every ledger starts with
  def self.seed(household)
    DEFAULTS.each_with_index do |(key, (name_zh, name_en)), position|
      household.supply_categories.create_with(name_zh:, name_en:, position:, perishable: PERISHABLE.include?(key)).find_or_create_by!(key:)
    end
  end

  # The ledger's "Other"
  def self.fallback(household)
    household.supply_categories.find_by(key: FALLBACK) || seed(household).then { household.supply_categories.find_by!(key: FALLBACK) }
  end

  # The starting category with this key, or Other when there is no key or it was archived or deleted
  def self.for_key(household, key)
    other = fallback(household)
    key.present? && household.supply_categories.active.find_by(key:) || other
  end

  # The category with this name (either language, any case), restored if it was archived; else a new
  # one at the end of the list, named in the language it was typed in (unsaved, with its errors,
  # when the name won't do)
  def self.named(household, name, locale: I18n.locale)
    name = name.to_s.squish
    found = household.supply_categories.to_a.find { |category| category.names.any? { it.casecmp?(name) } }
    return found.tap { it.update!(archived_at: nil) if it.archived_at } if found

    household.supply_categories.create((locale.to_s == "en" ? :name_en : :name_zh) => name, position: household.supply_categories.maximum(:position).to_i + 1)
  end

  def name = I18n.locale == :en ? name_en.presence || name_zh : name_zh.presence || name_en

  # Both names, Chinese first (Settings lists them side by side)
  def names = [ name_zh, name_en ].compact_blank

  # The language this category has no name in yet: "zh-TW", "en" or nil
  def missing_locale = name_zh.blank? ? "zh-TW" : ("en" if name_en.blank?)

  def fallback? = key == FALLBACK

  private

  # A name is the ledger's only one, in either language and any case (what `named` finds it by)
  def names_not_taken
    taken = household.supply_categories.where.not(id:).flat_map(&:names).map(&:downcase)
    { name_zh:, name_en: }.each { |attribute, value| errors.add(attribute, :taken) if value && taken.include?(value.downcase) }
  end
end
