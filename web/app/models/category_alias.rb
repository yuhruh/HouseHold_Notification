# An item name from the sheet mapped to a category, reused by later imports (PRD → Import mapping)
class CategoryAlias < ApplicationRecord
  belongs_to :household
  belongs_to :category

  normalizes :alias, with: ->(text) { text.unicode_normalize(:nfkc).strip }
  validates :alias, presence: true, uniqueness: { scope: :household_id }
  validate { errors.add(:category, :invalid) if category && category.household_id != household_id }
end
