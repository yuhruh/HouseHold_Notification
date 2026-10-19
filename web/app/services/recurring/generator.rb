module Recurring
  # Idempotent catch-up generation for one template (PRD §5): every period starting on or after
  # starts_on whose generation date ≤ the owner's local today and that has no record yet. A single
  # matching bill without a template (same type, category, details and period) is linked instead;
  # two or more matches link none and create nothing (the template page asks which one).
  class Generator
    Result = Data.define(:created, :linked, :ambiguous)

    def self.call(template, today:) = new(template, today).call

    def initialize(template, today)
      @template, @today = template, today
    end

    def call
      created, linked, ambiguous = [], [], []
      existing = @template.records.pluck(:period_year, :period_start_month).to_set
      @template.periods_from(@template.starts_on).lazy.take(RecurringTemplate::MAX_PERIODS_PER_RUN * 4).each do |period|
        break if @template.generation_date(period) > @today
        next if existing.include?([ period.start_year, period.start_month ])

        candidates = matching_bills(period)
        case candidates.size
        when 0 then (record = create_bill(period)) && created << record
        when 1 then link(candidates.first) && linked << candidates.first
        else ambiguous << period
        end
        break if created.size + linked.size >= RecurringTemplate::MAX_PERIODS_PER_RUN
      end
      Result.new(created:, linked:, ambiguous:)
    end

    def self.matching_bills(template, period)
      template.household.records.where(recurring_template_id: nil, record_type: template.record_type, category_id: template.category_id,
        period_year: period.start_year, period_start_month: period.start_month, period_end_year: period.end_year,
        period_end_month: period.end_month).where("COALESCE(details, '') = ?", template.details.to_s)
    end

    def create_bill(period)
      t = @template
      record = t.household.records.new(record_type: t.record_type, category: t.category, title: t.title, details: t.details,
        period:, currency: t.currency, amount_required: (t.default_amount if t.amount_fixed?), due_on: t.due_on_for(period),
        payment_method: t.payment_method, recurring_template: t)
      if record.due_on.nil? && !t.reminder_none?
        record.reminder_frequency = t.default_reminder_frequency
        record.reminder_starts_on = @today + 1
      end
      Record.transaction(requires_new: true) do
        record.save!
        RecordEvent.log!(record, :created, user: nil)
      end
      record
    rescue ActiveRecord::RecordNotUnique
      nil # a concurrent run created it
    end

    private

    def matching_bills(period) = self.class.matching_bills(@template, period).to_a

    def link(record)
      record.update!(recurring_template: @template)
    end
  end
end
