module Reminders
  # Digest text comes from today, not from the stage (PRD §6): a due-date reminder delivered a day
  # late reads "1 day overdue".
  module Wording
    FORMATTER = Object.new.extend(ActionView::Helpers::NumberHelper, MoneyHelper)

    module_function

    def line(record, kind, today)
      parts = [ record.title, record.details.presence, record.period.to_s, outstanding(record) ].compact
      "#{parts.join(' · ')}: #{status(record, kind, today)}"
    end

    def status(record, kind, today)
      case kind
      when "no_due_repeat" then I18n.t("reminders.wording.no_due_date")
      when "snooze_ended" then I18n.t("reminders.wording.snooze_ended")
      when /\Anext_/ then relative("maintenance", record.next_due_on, today)
      else
        text = relative(record.maintenance? ? "maintenance" : "bill", record.due_on, today)
        kind == "overdue_final" ? "#{text}#{I18n.t('reminders.wording.final')}" : text
      end
    end

    def relative(scope, date, today)
      days = (date - today).to_i
      if days.positive? then I18n.t("reminders.wording.#{scope}.due_in", count: days)
      elsif days.zero? then I18n.t("reminders.wording.#{scope}.due_today")
      else I18n.t("reminders.wording.#{scope}.overdue", count: -days)
      end
    end

    def outstanding(record)
      return unless record.amount_required
      FORMATTER.money(record.amount_required - (record.amount_paid || 0), record.currency)
    end
  end
end
