# What a bill barcode's biller code (the last 3 characters of the first barcode, e.g. "6AM") means for a
# household: its category, and how many days after the due date the barcode's deadline falls (taxes
# print "繳納期間屆滿後3日", so 3; most utility bills 0). Asked once, then remembered.
class BillerCode < ApplicationRecord
  belongs_to :household
  belongs_to :category

  validates :code, format: { with: /\A[0-9A-Z]{3}\z/ }, uniqueness: { scope: :household_id }
  validates :deadline_offset_days, numericality: { only_integer: true, in: 0..10 }
  validate :category_in_household

  private

  def category_in_household
    errors.add(:category, :invalid) if category && category.household_id != household_id
  end
end
