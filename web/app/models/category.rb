# Per-household categories, seeded per type (PRD §3). detail_required is true only for the
# seeded 牌照稅 and 保險 and isn't editable in v1.
class Category < ApplicationRecord
  RECORD_TYPES = { expense: "expense", maintenance: "maintenance", tax: "tax" }.freeze

  belongs_to :household
  has_many :records, dependent: :restrict_with_error
  has_many :category_aliases, dependent: :destroy

  enum :record_type, RECORD_TYPES, validate: true

  validates :name_zh, presence: true, length: { maximum: 40 }, uniqueness: { scope: %i[household_id record_type] }
  validates :name_en, length: { maximum: 40 }

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:record_type, :position, :id) }

  def name = I18n.locale == :en ? name_en.presence || name_zh : name_zh
  def detail_label = I18n.locale == :en ? detail_label_en.presence || detail_label_zh : detail_label_zh
end
