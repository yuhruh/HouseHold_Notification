module Records
  # Bills › To Pay (PRD §6), in the viewer's local today: what's overdue, due in the next 30 days,
  # maintenance coming up, due later and without a due date. The page lists them; the switch at the
  # top of both Bills views shows how many there are. `scheduled` is each recurring bill's next period
  # the daily job hasn't created yet: shown so it isn't missing, not counted (nothing to pay yet).
  class ToPay
    HORIZON = 30
    SECTIONS = %i[overdue soon maintenance later no_due].freeze
    Scheduled = Data.define(:template, :period, :due_on, :creates_on) do
      # When it's due, or (a bill without a due day) when its period starts
      def date = due_on || Date.new(period.start_year, period.start_month, 1)
    end

    attr_reader :today

    def initialize(household, today: Date.current)
      @household = household
      @today = today
    end

    def overdue = @overdue ||= unpaid.where(due_on: ...today).order(:due_on).to_a
    def soon = @soon ||= unpaid.where(due_on: today..(today + HORIZON)).order(:due_on).to_a
    def maintenance = @maintenance ||= @household.records.where(next_due_on: ..(today + HORIZON)).includes(:category).order(:next_due_on).to_a
    # Unpaid bills due after the 30 days, so nothing unpaid is missing from the page
    def later = @later ||= unpaid.where(due_on: (today + HORIZON + 1)..).order(:due_on).to_a
    def no_due = @no_due ||= unpaid.where(due_on: nil).order(:period_year, :period_start_month).to_a

    def scheduled
      @scheduled ||= @household.recurring_templates.includes(:category).filter_map do |template|
        period = template.next_scheduled_period(today) or next
        Scheduled.new(template:, period:, due_on: template.due_on_for(period), creates_on: template.generation_date(period))
      end.sort_by(&:date)
    end

    def sections = SECTIONS.map { [ it, public_send(it) ] }
    def count = sections.sum { |_, list| list.size }

    private

    def unpaid = @household.records.where(settled: false).includes(:category)
  end
end
