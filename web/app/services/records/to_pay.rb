module Records
  # Bills › To Pay and Bills › Coming Up (PRD §6), in the viewer's local today.
  # To Pay: what needs doing now (overdue, due in the next 30 days, maintenance coming up, no due date);
  # its count is the red number on the Bills tabs. Coming Up: what isn't due yet, soonest first:
  # unpaid bills due after the 30 days, and each recurring bill's next period the daily job hasn't
  # created yet (`scheduled`). Nothing on Coming Up is counted as to pay.
  class ToPay
    HORIZON = 30
    SECTIONS = %i[overdue soon maintenance no_due].freeze

    Scheduled = Data.define(:template, :period, :due_on, :creates_on) do
      # When it's due, or (a bill without a due day) when its period starts
      def date = due_on || Date.new(period.start_year, period.start_month, 1)
      # It joins To Pay once created and, with a due date, once that's within the 30 days
      def to_pay_on = due_on ? [ creates_on, due_on - HORIZON ].max : creates_on
    end

    attr_reader :today

    def initialize(household, today: Date.current)
      @household = household
      @today = today
    end

    def overdue = @overdue ||= unpaid.where(due_on: ...today).order(:due_on).to_a
    def soon = @soon ||= unpaid.where(due_on: today..(today + HORIZON)).order(:due_on).to_a
    def maintenance = @maintenance ||= @household.records.where(next_due_on: ..(today + HORIZON)).includes(:category).order(:next_due_on).to_a
    def no_due = @no_due ||= unpaid.where(due_on: nil).order(:period_year, :period_start_month).to_a

    def sections = SECTIONS.map { [ it, public_send(it) ] }
    def count = sections.sum { |_, list| list.size }

    # Unpaid bills due after the 30 days
    def later = @later ||= unpaid.where(due_on: (today + HORIZON + 1)..).order(:due_on).to_a

    def scheduled
      @scheduled ||= @household.recurring_templates.includes(:category).filter_map do |template|
        period = template.next_scheduled_period(today) or next
        Scheduled.new(template:, period:, due_on: template.due_on_for(period), creates_on: template.generation_date(period))
      end.sort_by(&:date)
    end

    # Coming Up: later bills and scheduled ones together, by the date they're due
    def coming_up = @coming_up ||= (later + scheduled).sort_by { [ date_of(it), it.is_a?(Scheduled) ? 1 : 0 ] }
    def coming_up_count = coming_up.size
    # The Coming Up item that joins To Pay first (To Pay's "Next up" line)
    def next_up = coming_up.min_by { to_pay_on(it) }

    def date_of(item) = item.is_a?(Scheduled) ? item.date : item.due_on
    def to_pay_on(item) = item.is_a?(Scheduled) ? item.to_pay_on : item.due_on - HORIZON

    private

    def unpaid = @household.records.where(settled: false).includes(:category)
  end
end
