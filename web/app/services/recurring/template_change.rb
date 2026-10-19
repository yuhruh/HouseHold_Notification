module Recurring
  # Saving a template updates its untouched unpaid bills, latest change wins (PRD §5):
  # - amount (amount_fixed templates): every untouched bill gets the new amount;
  # - interval / span / due day: the bill whose period already started is updated in place,
  #   bills for periods not yet started are deleted and regenerated under the new schedule.
  # `changes` lists every affected bill before → after for the confirmation; `apply!` does it all
  # in one transaction, with a template_updated (or deleted) record event per bill.
  class TemplateChange
    SCHEDULE = %w[interval_months anchor_month period_span_months due_day due_month_offset].freeze

    Change = Data.define(:record, :action, :before, :after)

    attr_reader :template

    def initialize(template, attributes, today:)
      @template, @today = template, today
      @template.assign_attributes(attributes)
    end

    def valid? = @template.valid?

    def changes
      @changes ||= begin
        untouched = @template.persisted? ? @template.records.where(settled: false, paid_on: nil, amount_paid: nil).order(:period_year, :period_start_month).to_a : []
        untouched.filter_map { |record| change_for(record) }
      end
    end

    def apply!(user:)
      RecurringTemplate.transaction do
        @template.save!
        changes.each do |change|
          if change.action == :delete
            RecordEvent.log!(change.record, :deleted, user:)
            change.record.destroy!
          else
            change.record.update!(change.after)
            RecordEvent.log!(change.record, :template_updated, user:)
          end
        end
        Generator.call(@template, today: @today)
      end
    end

    private

    def schedule_changed? = (@template.changed & SCHEDULE).any?
    def amount_changed? = @template.amount_fixed? && (@template.default_amount_changed? || @template.amount_fixed_changed?)

    def change_for(record)
      started = Date.new(record.period_year, record.period_start_month, 1) <= @today
      return Change.new(record:, action: :delete, before: summary(record), after: nil) if schedule_changed? && !started

      after = {}
      after[:amount_required] = @template.default_amount if amount_changed? && record.amount_required != @template.default_amount
      if schedule_changed?
        index = record.period_year * 12 + record.period_start_month - 1
        period = @template.period_at(index)
        after[:period_end_year], after[:period_end_month] = period.end_year, period.end_month
        after[:due_on] = @template.due_on_for(period)
        after.reject! { |key, value| record[key] == value }
      end
      return if after.empty?

      Change.new(record:, action: :update, before: summary(record), after:)
    end

    def summary(record) = record.slice(:amount_required, :period_end_year, :period_end_month, :due_on).symbolize_keys
  end
end
