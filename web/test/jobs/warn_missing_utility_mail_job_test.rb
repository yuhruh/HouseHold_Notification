require "test_helper"

class WarnMissingUtilityMailJobTest < ActiveJob::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    travel_to Time.zone.parse("2026-10-08 10:00") do
      @account = @home.create_electricity_account!(category: @home.categories.find_by!(name_zh: "電費"), last_success_at: Time.current)
    end
  end

  def warnings = Notification.where(household: @home, kind: "utility_mail_missing")

  test "nothing while 台電's next email isn't a week late" do
    travel_to Time.zone.parse("2026-12-14 10:00") { WarnMissingUtilityMailJob.perform_now }
    assert_empty warnings
  end

  test "a week after the expected day the owner is told once, in their language, with a link to the page" do
    users(:alex).update!(locale: "en")
    travel_to Time.zone.parse("2026-12-15 10:00") do
      2.times { WarnMissingUtilityMailJob.perform_now }
    end
    warning = warnings.sole
    assert_equal users(:alex), warning.user
    assert_match(/no 台電 bill email yet/, warning.title)
    assert_match(/expected around 2026-12-08, 2 months after the last one \(2026-10-08\)/, warning.body)
    assert_equal "/h/#{@home.id}/electricity_account", warning.url
    assert_equal Date.new(2026, 12, 8), @account.reload.missing_mail_warned_for
  end

  test "a bill that arrives resets the clock; another missed bill is warned about again" do
    travel_to(Time.zone.parse("2026-12-15 10:00")) { WarnMissingUtilityMailJob.perform_now }
    travel_to(Time.zone.parse("2027-02-16 10:00")) { WarnMissingUtilityMailJob.perform_now }
    assert_equal 2, warnings.count, "still nothing two months later: the next bill is late too"

    travel_to(Time.zone.parse("2027-02-20 10:00")) do
      @account.update!(last_success_at: Time.current)
      WarnMissingUtilityMailJob.perform_now
    end
    assert_equal 2, warnings.count
  end

  test "it counts from the last bill's 收費日 once one has been read, whoever forwarded it" do
    @account.update!(last_success_at: nil, created_at: Time.zone.parse("2026-11-15 10:00"), last_bill_on: Date.new(2026, 10, 8))
    assert_equal Date.new(2026, 12, 8), @account.next_mail_expected_on
    travel_to(Time.zone.parse("2026-12-15 10:00")) { WarnMissingUtilityMailJob.perform_now }
    assert_match(/上一封 2026-10-08/, warnings.sole.body)
  end

  test "before any email it counts from the day Electricity was turned on" do
    @account.update!(last_success_at: nil, created_at: Time.zone.parse("2026-11-15 10:00"))
    travel_to(Time.zone.parse("2027-01-22 10:00")) { WarnMissingUtilityMailJob.perform_now }
    assert_match(/開啟電費功能（2026-11-15）後還沒收到/, warnings.sole.body)
  end
end
