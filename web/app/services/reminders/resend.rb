module Reminders
  # A resend carries only the items that still need attention: unpaid bills, or next-due dates
  # that are still set (PRD §6)
  module Resend
    module_function

    def remaining_logs(delivery)
      delivery.reminder_logs.includes(:record).select do |log|
        log.kind.start_with?("next_") ? log.record.next_due_on.present? : !log.record.settled
      end
    end
  end
end
