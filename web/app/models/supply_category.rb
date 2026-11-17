# A ledger's own supply categories (Settings › Categories › Supplies). Each ledger starts with six
# (DEFAULTS); owners and co-owners add more, from the item form too. `key` marks a starting one, so
# what a barcode lookup guesses ("kitchen") still finds it after a rename. "Other" always stays, for
# an item without a category. perishable: expiry alerts a week ahead instead of a month.
class SupplyCategory < ApplicationRecord
  DEFAULTS = { "toiletries" => %w[盥洗用品 Toiletries], "cleaning" => %w[清潔用品 Cleaning], "kitchen" => %w[廚房用品 Kitchen],
               "food_drink" => [ "食品飲料", "Food & drink" ], "health" => %w[保健醫療 Health], "other" => %w[其他 Other] }.freeze
  KEYS = DEFAULTS.keys.freeze
  PERISHABLE = %w[food_drink health].freeze
  FALLBACK = "other".freeze

  belongs_to :household
  has_many :supplies, dependent: :restrict_with_error

  normalizes :name_zh, :name_en, with: ->(name) { name.to_s.squish.presence }

  validates :name_zh, presence: true, length: { maximum: 40 }, uniqueness: { scope: :household_id, case_sensitive: false }
  validates :name_en, length: { maximum: 40 }
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
  # one at the end of the list (unsaved, with its errors, when the name won't do)
  def self.named(household, name)
    name = name.to_s.squish
    found = household.supply_categories.to_a.find { |category| [ category.name_zh, category.name_en ].compact.any? { it.casecmp?(name) } }
    return found.tap { it.update!(archived_at: nil) if it.archived_at } if found

    household.supply_categories.create(name_zh: name, position: household.supply_categories.maximum(:position).to_i + 1)
  end

  def name = I18n.locale == :en ? name_en.presence || name_zh : name_zh
  def fallback? = key == FALLBACK
end
