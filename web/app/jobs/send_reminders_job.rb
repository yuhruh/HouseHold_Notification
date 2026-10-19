# Hourly reminder run (PRD §6). Pings the "reminder job ran" heartbeat (REMINDER_HEARTBEAT_URL,
# grace 3h) at the end, /fail on an unexpected error, and queues the owner's failure summary.
class SendRemindersJob < ApplicationJob
  queue_as :default

  def perform
    Reminders::Run.call
    OwnerFailureSummaryJob.perform_later # always after this hour's dispatch
    Heartbeat.ping(ENV["REMINDER_HEARTBEAT_URL"])
  rescue StandardError
    Heartbeat.ping(ENV["REMINDER_HEARTBEAT_URL"], "/fail")
    raise
  end
end
