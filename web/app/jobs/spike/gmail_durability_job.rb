module Spike
  # M0 check X8: test mail through the Gmail API twice a day for 8 days, to the addresses in
  # X8_RECIPIENTS (comma-separated). A revoked or expired token raises, so Sentry alerts the owner.
  # Stops by itself after LAST_DAY; removed with the other spikes.
  class GmailDurabilityJob < ApplicationJob
    queue_as :default

    LAST_DAY = Date.new(2026, 10, 26)

    def perform
      return if Time.current.in_time_zone("Asia/Taipei").to_date > LAST_DAY

      ENV.fetch("X8_RECIPIENTS", "").split(",").map(&:strip).compact_blank.each do |to|
        TestMailer.with(to:).hello.deliver_now
      end
    end
  end
end
