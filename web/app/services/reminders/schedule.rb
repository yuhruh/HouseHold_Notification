module Reminders
  # When each reminder stage is due (PRD §6). All dates are the recipient's local dates.
  # Due date D: due soon D − lead, due today D, overdue D+3 … D+30 (10), final notice D+33.
  # "Restart reminders" on R starts a new cycle: overdue R, R+3 … R+27, final R+30.
  # Maintenance next-due N follows the same cadence. Records without a due date repeat by their
  # frequency from reminder_starts_on. Only the latest stage whose date has come is sent.
  module Schedule
    OVERDUE_EVERY = 3
    OVERDUE_COUNT = 10
    STEP_DAYS = { "daily" => 1, "every_3_days" => 3, "weekly" => 7, "biweekly" => 14 }.freeze
    DUE_KINDS = { soon: "due_soon", today: "due_today", overdue: "overdue", final: "overdue_final" }.freeze
    NEXT_KINDS = { soon: "next_due_soon", today: "next_due_today", overdue: "next_due_overdue", final: "next_due_final" }.freeze

    module_function

    # [kind, scheduled_on] of the latest due stage, or nil
    def current_stage(record, local_date, lead_days:)
      if record.due_on && !record.settled
        cadence(record.due_on, local_date, lead_days, record.reminders_restarted_on, DUE_KINDS)
      elsif record.due_on.nil? && !record.settled && !record.reminder_none?
        repeat = scheduled_repeat(record, local_date)
        [ "no_due_repeat", repeat ] if repeat
      end
    end

    def next_due_stage(record, local_date, lead_days:)
      cadence(record.next_due_on, local_date, lead_days, nil, NEXT_KINDS) if record.next_due_on
    end

    def cadence(due, today, lead_days, restarted_on, kinds)
      stages = []
      stages << [ kinds[:soon], due - lead_days ] if lead_days.positive? && due - lead_days <= today
      stages << [ kinds[:today], due ] if due <= today
      if restarted_on && restarted_on > due
        base, first = restarted_on, 0
      else
        base, first = due, 1
      end
      steps = ((today - base).to_i / OVERDUE_EVERY)
      if steps >= first
        last = [ steps, first + OVERDUE_COUNT - 1 ].min
        stages << [ kinds[:overdue], base + last * OVERDUE_EVERY ]
      end
      final = base + (first + OVERDUE_COUNT) * OVERDUE_EVERY
      stages << [ kinds[:final], final ] if final <= today
      stages.last
    end

    def reminders_stopped?(record, today)
      return false unless record.due_on && !record.settled
      cadence(record.due_on, today, 0, record.reminders_restarted_on, DUE_KINDS)&.first == "overdue_final"
    end

    def scheduled_repeat(record, today)
      start = record.reminder_starts_on || record.created_at.to_date + 1
      return if start > today

      if record.reminder_frequency == "monthly"
        months = (today.year * 12 + today.month) - (start.year * 12 + start.month)
        date = clamp_day(start >> months, start.day)
        date = clamp_day(start >> (months - 1), start.day) if date > today
        date
      else
        step = STEP_DAYS.fetch(record.reminder_frequency)
        start + ((today - start).to_i / step) * step
      end
    end

    def clamp_day(month_date, day) = Date.new(month_date.year, month_date.month, [ day, month_date.end_of_month.day ].min)
  end
end
