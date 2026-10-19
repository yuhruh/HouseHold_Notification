# Daily: every template generates its due bills in the household owner's time zone (PRD §5, §11).
# Pings its Healthchecks.io check (GENERATE_HEARTBEAT_URL, grace 26h); a failure pings /fail.
class GenerateRecurringRecordsJob < ApplicationJob
  queue_as :default

  def perform
    RecurringTemplate.includes(household: :owner).find_each do |template|
      today = Time.use_zone(template.household.time_zone) { Date.current }
      Recurring::Generator.call(template, today:)
    end
    Heartbeat.ping(ENV["GENERATE_HEARTBEAT_URL"])
  rescue StandardError
    Heartbeat.ping(ENV["GENERATE_HEARTBEAT_URL"], "/fail")
    raise
  end
end
