# A bill or maintenance entry (PRD §1). Status is derived; only rule 1 (paid) is stored, as
# `settled`, so "unpaid" means settled = false everywhere. Every write goes through save!.
class Record < ApplicationRecord
  MAX_AMOUNT = BigDecimal("10000000000")
  REMINDER_FREQUENCIES = %w[none daily every_3_days weekly biweekly monthly].freeze

  belongs_to :household
  belongs_to :category
  belongs_to :payment_method, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :record_type, Category::RECORD_TYPES, validate: true
  enum :reminder_frequency, REMINDER_FREQUENCIES.index_by(&:itself), prefix: :reminder, validate: true

  validates :title, presence: true, length: { maximum: 100 }
  validates :details, length: { maximum: 200 }
  validates :payment_note, length: { maximum: 2000 }
  validates :currency, inclusion: { in: Household::CURRENCIES }
  validates :amount_required, :amount_paid, numericality: { greater_than_or_equal_to: 0, less_than: MAX_AMOUNT }, allow_nil: true
  validates :period_year, numericality: { only_integer: true, in: 2000..2100 }
  validates :period_start_month, :period_end_month, numericality: { only_integer: true, in: 1..12 }
  validate :period_end_year_follows_rule
  validate :belongs_to_same_household
  validate :details_for_identifier_category
  validate :amounts_consistent
  validates :import_key, presence: true, on: :import
  validate :paid_on_not_in_future, on: :import

  before_validation { self.reminder_frequency = "none" if due_on.present? }
  before_save { self.settled = paid_by_rule? }
  before_create :assign_record_no

  def period
    Period.new(start_year: period_year, start_month: period_start_month, end_year: period_end_year, end_month: period_end_month)
  end

  def period=(period)
    self.period_year, self.period_start_month, self.period_end_year, self.period_end_month = period.deconstruct
  end

  # Status rules, in order (PRD §1). `today` is the viewer's or recipient's local date.
  def status(today: Date.current)
    if paid_by_rule? then :paid
    elsif due_on && due_on < today then :overdue
    elsif paid_on && amount_paid && amount_required && amount_paid < amount_required then :partial
    else :unpaid
    end
  end

  # Rule 1: Expense/Tax need Paid = Required with a paid date; Maintenance needs a finished date
  # and either no Required or Paid = Required.
  def paid_by_rule?
    return false unless paid_on
    if maintenance?
      amount_required.nil? || amount_paid == amount_required
    else
      amount_required.present? && amount_paid == amount_required
    end
  end

  private

  def period_end_year_follows_rule
    return unless period_year && period_start_month && period_end_month
    expected = period_end_month < period_start_month ? period_year + 1 : period_year
    errors.add(:period_end_year, :year_boundary) unless period_end_year == expected
  end

  def belongs_to_same_household
    errors.add(:category, :invalid) if category && category.household_id != household_id
    errors.add(:category, :wrong_type) if category && record_type && category.record_type != record_type
    errors.add(:payment_method, :invalid) if payment_method && payment_method.household_id != household_id
  end

  def details_for_identifier_category
    return unless category&.detail_required && details.blank?
    errors.add(:details, :required_for_category, label: category.detail_label, category: category.name)
  end

  # PRD §1 validations: a payment needs a date, Paid ≤ Required, and a paid date needs the amounts
  def amounts_consistent
    errors.add(:paid_on, :required_for_payment) if amount_paid&.positive? && paid_on.nil?
    errors.add(:amount_paid, :exceeds_required) if amount_paid && amount_required && amount_paid > amount_required
    return unless paid_on

    errors.add(:amount_required, :required_with_paid_on) if !maintenance? && amount_required.nil?
    errors.add(:amount_paid, :required_with_paid_on) if amount_paid.nil? && (amount_required || !maintenance?)
  end

  def paid_on_not_in_future
    today = Time.current.in_time_zone(household&.time_zone || User::DEFAULT_TIME_ZONE).to_date
    errors.add(:paid_on, :in_future) if paid_on && paid_on > today
  end

  def assign_record_no
    self.record_no ||= self.class.connection.select_value(self.class.sanitize_sql_array(
      [ "UPDATE households SET next_record_no = next_record_no + 1 WHERE id = ? RETURNING next_record_no", household_id ]
    ))
  end
end
