# A ledger's link to a utility company, one per kind (single-table inheritance on `type`):
# GasAccount (欣桃天然氣, checked every working day), and ElectricityAccount (台電) and WaterAccount
# (台水), from forwarded emails. Bills go in `category`; Utilities::BillSync adds and fills them in
# and marks them paid, and `activity` keeps the last lines it reported.
class UtilityAccount < ApplicationRecord
  ACTIVITY_KEPT = 20
  ACTIVITY_TEXT = 200

  belongs_to :household
  belongs_to :category
  belongs_to :payment_method, optional: true

  normalizes :customer_code, with: ->(code) { code.to_s.gsub(/\D/, "").presence }

  validates :household_id, uniqueness: { scope: :type }
  validate :category_is_an_expense_of_this_ledger
  validate :payment_method_of_this_ledger

  scope :enabled, -> { where(enabled: true) }

  # The number as shown on screen: only its last 4 digits
  def masked_code = customer_code && "…#{customer_code.last(4)}"

  # Newest first; each line is {"at", "kind", "record_id", "period", "amount", "recorded", "due_on"}.
  # Text in a line can come straight from an email (its sender, its subject), so it's cut to
  # ACTIVITY_TEXT characters and loses what the database can't store (broken bytes, NUL).
  def add_activity(lines)
    lines = lines.map { |line| line.transform_values { it.is_a?(String) ? it.dup.force_encoding(Encoding::UTF_8).scrub("?").delete("\u0000").truncate(ACTIVITY_TEXT) : it } }
    self.activity = (lines.map { it.merge("at" => Time.current.iso8601) } + activity).first(ACTIVITY_KEPT)
  end

  def connected? = last_success_at.present? && last_error.blank?

  private

  def category_is_an_expense_of_this_ledger
    return unless category
    errors.add(:category, :invalid) unless category.household_id == household_id && category.expense?
  end

  def payment_method_of_this_ledger
    errors.add(:payment_method, :invalid) if payment_method && payment_method.household_id != household_id
  end
end
