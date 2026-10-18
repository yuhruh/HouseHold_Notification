module Auth
  # Daily (PRD §10): unconfirmed sign-ups older than 7 days with no Google identity, expired sessions
  # and expired Google handoffs.
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      User.stale_unconfirmed.find_each(&:destroy!)
      Session.expired.delete_all
      AuthHandoff.expired.delete_all
    end
  end
end
