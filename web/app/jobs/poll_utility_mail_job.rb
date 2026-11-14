# Every 5 minutes: reads what members' Gmail forwarded to the ledgers' addresses
# (Utilities::ForwardedMail). Until the app's Gmail has been re-authorized with read access
# (`bin/rails gmail:authorize`), or while Gmail is unreachable, it only logs and tries next time.
class PollUtilityMailJob < ApplicationJob
  queue_as :default

  def perform
    Utilities::ForwardedMail.call
  rescue *Utilities::Inbox::UNAVAILABLE => e
    Rails.logger.warn("[PollUtilityMailJob] Gmail can't be read: #{e.class}: #{e.message.truncate(200)}")
  end
end
