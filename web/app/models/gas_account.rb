# A ledger's 欣桃天然氣 用戶編號 (Ledger settings › Gas account). One per ledger, and one ledger per
# number. Every working day Utilities::ShintaoGas::Sync adds its new bills to `category` and marks
# them paid once the gas company shows them paid; `activity` keeps the last lines it reported.
class GasAccount < ApplicationRecord
  ACTIVITY_KEPT = 20

  belongs_to :household
  belongs_to :category
  belongs_to :payment_method, optional: true

  normalizes :customer_code, with: ->(code) { code.to_s.gsub(/\D/, "") }

  validates :customer_code, format: { with: /\A\d{10}\z/ }, uniqueness: true
  validates :household_id, uniqueness: true
  validate :category_is_an_expense_of_this_ledger
  validate :payment_method_of_this_ledger

  scope :enabled, -> { where(enabled: true) }

  # The number as shown on screen: only its last 4 digits
  def masked_code = "…#{customer_code.to_s.last(4)}"

  # Newest first; each line is {"at", "kind", "record_id", "period", "amount", "recorded", "due_on"}
  def add_activity(lines)
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
