# A repeating bill (PRD §5): periods start in anchor_month and every interval_months after it,
# each spanning period_span_months. Deactivating = deleting; its bills are kept, unlinked.
class RecurringTemplate < ApplicationRecord
  MAX_PERIODS_PER_RUN = 24

  belongs_to :household
  belongs_to :category
  belongs_to :payment_method, optional: true
  has_many :records, dependent: :nullify

  enum :record_type, Category::RECORD_TYPES, validate: true
  enum :default_reminder_frequency, Record::REMINDER_FREQUENCIES.index_by(&:itself), prefix: :reminder, validate: true

  validates :title, presence: true, length: { maximum: 100 }
  validates :details, length: { maximum: 200 }
  validates :currency, inclusion: { in: Household::CURRENCIES }
  validates :default_amount, numericality: { greater_than_or_equal_to: 0, less_than: Record::MAX_AMOUNT }, allow_nil: true
  validates :interval_months, numericality: { only_integer: true, in: 1..60 }
  validates :anchor_month, numericality: { only_integer: true, in: 1..12 }
  validates :period_span_months, numericality: { only_integer: true, in: 1..12 }
  validates :due_day, numericality: { only_integer: true, in: 1..31 }, allow_nil: true
  validates :due_month_offset, numericality: { only_integer: true, in: 0..24 }
  validates :lead_days, numericality: { only_integer: true, in: 0..90 }
  validates :starts_on, presence: true
  validates :default_amount, presence: true, if: :amount_fixed?
  validate :same_household
  validate :details_for_identifier_category

  before_validation :fill_derived_fields

  # Period start months as year * 12 + (month - 1)
  def periods_from(date)
    return enum_for(:periods_from, date) unless block_given?

    target = date.year * 12 + date.month - 1
    index = date.year * 12 + anchor_month - 1
    index -= interval_months while index > target
    index += interval_months while index < target
    loop do
      yield period_at(index)
      index += interval_months
    end
  end

  def period_at(index)
    finish = index + period_span_months - 1
    Period.new(start_year: index / 12, start_month: index % 12 + 1, end_year: finish / 12, end_month: finish % 12 + 1)
  end

  def due_on_for(period)
    return unless due_day
    month = Date.new(period.start_year, period.start_month, 1) >> due_month_offset
    Date.new(month.year, month.month, [ due_day, month.end_of_month.day ].min)
  end

  # Generated lead_days before the due date, or before the period starts when there's no due day
  def generation_date(period) = (due_on_for(period) || Date.new(period.start_year, period.start_month, 1)) - lead_days

  def next_period(today) = periods_from(today.beginning_of_month).first

  # "Make this recurring" on a record: the template starts at the record's period (so the record is
  # linked as its first bill) and repeats every period length (1月-2月 → every 2 months)
  def self.attributes_from(record)
    start = record.period_year * 12 + record.period_start_month - 1
    span = record.period_end_year * 12 + record.period_end_month - 1 - start + 1
    offset = record.due_on && (record.due_on.year * 12 + record.due_on.month - 1 - start)
    due = offset&.between?(0, 24)
    { category_id: record.category_id, title: record.title, details: record.details, currency: record.currency,
      default_amount: record.amount_required, payment_method_id: record.payment_method_id,
      interval_months: span, anchor_month: record.period_start_month, period_span_months: span,
      starts_on: Date.new(record.period_year, record.period_start_month, 1),
      due_day: (record.due_on.day if due), due_month_offset: (due ? offset : 0),
      default_reminder_frequency: (due ? "none" : record.reminder_frequency) }
  end

  # Periods due for generation where 2+ bills without a template match: someone has to pick one
  def ambiguous_periods(today)
    existing = records.pluck(:period_year, :period_start_month).to_set
    periods_from(starts_on).lazy.take(MAX_PERIODS_PER_RUN * 4).take_while { |p| generation_date(p) <= today }
      .reject { |p| existing.include?([ p.start_year, p.start_month ]) }
      .select { |p| Recurring::Generator.matching_bills(self, p).count > 1 }.to_a
  end

  private

  def fill_derived_fields
    if category
      self.record_type = category.record_type
      self.title = category.name_zh if title.blank?
    end
    self.period_span_months ||= interval_months.to_i.clamp(1, 12) if interval_months
    self.anchor_month ||= starts_on.month if starts_on
    self.default_reminder_frequency = "none" if due_day.present?
  end

  def same_household
    errors.add(:category, :invalid) if category && category.household_id != household_id
    errors.add(:payment_method, :invalid) if payment_method && payment_method.household_id != household_id
  end

  def details_for_identifier_category
    return unless category&.detail_required && details.blank?
    errors.add(:details, :required_for_category, label: category.detail_label, category: category.name)
  end
end
