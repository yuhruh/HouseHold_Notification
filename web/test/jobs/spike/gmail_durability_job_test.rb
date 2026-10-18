require "test_helper"

class Spike::GmailDurabilityJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup { @recipients = ENV["X8_RECIPIENTS"] }
  teardown { ENV["X8_RECIPIENTS"] = @recipients }

  test "mails every recipient" do
    ENV["X8_RECIPIENTS"] = "a@example.com, b@example.com"
    travel_to Time.zone.parse("2026-10-20 09:00 +08:00") do
      assert_emails(2) { Spike::GmailDurabilityJob.perform_now }
    end
  end

  test "sends nothing without recipients" do
    ENV["X8_RECIPIENTS"] = nil
    assert_no_emails { Spike::GmailDurabilityJob.perform_now }
  end

  test "stops after the last day in Taipei" do
    ENV["X8_RECIPIENTS"] = "a@example.com"
    travel_to Time.zone.parse("2026-10-26 20:00 +08:00") do
      assert_emails(1) { Spike::GmailDurabilityJob.perform_now }
    end
    travel_to Time.zone.parse("2026-10-27 09:00 +08:00") do
      assert_no_emails { Spike::GmailDurabilityJob.perform_now }
    end
  end
end
