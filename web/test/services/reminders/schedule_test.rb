require "test_helper"

class Reminders::ScheduleTest < ActiveSupport::TestCase
  D = Date.new(2026, 10, 20)

  def bill(**attrs) = Record.new({ record_type: "expense", due_on: D, settled: false, reminder_frequency: "none" }.merge(attrs))
  def stage(on, lead: 3, **attrs) = Reminders::Schedule.current_stage(bill(**attrs), on, lead_days: lead)

  test "the PRD cadence for D = Oct 20, lead 3" do
    assert_nil stage(Date.new(2026, 10, 16))
    assert_equal [ "due_soon", Date.new(2026, 10, 17) ], stage(Date.new(2026, 10, 17))
    assert_equal [ "due_soon", Date.new(2026, 10, 17) ], stage(Date.new(2026, 10, 19)), "no sends in between: same claim"
    assert_equal [ "due_today", D ], stage(D)
    assert_equal [ "overdue", Date.new(2026, 10, 23) ], stage(Date.new(2026, 10, 23))
    assert_equal [ "overdue", Date.new(2026, 10, 26) ], stage(Date.new(2026, 10, 27))
    assert_equal [ "overdue", Date.new(2026, 11, 19) ], stage(Date.new(2026, 11, 21)), "10th overdue is D + 30"
    assert_equal [ "overdue_final", Date.new(2026, 11, 22) ], stage(Date.new(2026, 11, 22))
    assert_equal [ "overdue_final", Date.new(2026, 11, 22) ], stage(Date.new(2027, 1, 1)), "after the cap nothing new"
  end

  test "lead days 0 skips due soon; a paid record has no stage" do
    assert_nil stage(Date.new(2026, 10, 19), lead: 0)
    assert_nil stage(D, settled: true)
  end

  test "catch-up sends only the latest stage" do
    assert_equal "overdue", stage(Date.new(2026, 10, 23)).first, "down from D to D+3: only overdue"
  end

  test "restart starts a new cycle of 10 overdue reminders from the restart day" do
    r = Date.new(2026, 12, 1)
    assert_equal [ "overdue", r ], stage(r, reminders_restarted_on: r)
    assert_equal [ "overdue", r + 27 ], stage(r + 29, reminders_restarted_on: r)
    assert_equal [ "overdue_final", r + 30 ], stage(r + 30, reminders_restarted_on: r)
    assert Reminders::Schedule.reminders_stopped?(bill, Date.new(2026, 11, 22))
    assert_not Reminders::Schedule.reminders_stopped?(bill(reminders_restarted_on: r), r + 1)
  end

  test "records without a due date repeat by their frequency; monthly clamps to month end" do
    weekly = bill(due_on: nil, reminder_frequency: "weekly", reminder_starts_on: Date.new(2026, 10, 1))
    assert_equal [ "no_due_repeat", Date.new(2026, 10, 15) ], Reminders::Schedule.current_stage(weekly, Date.new(2026, 10, 20), lead_days: 3)
    monthly = bill(due_on: nil, reminder_frequency: "monthly", reminder_starts_on: Date.new(2026, 1, 31))
    assert_equal Date.new(2026, 2, 28), Reminders::Schedule.current_stage(monthly, Date.new(2026, 3, 30), lead_days: 3).last
    assert_equal Date.new(2026, 3, 31), Reminders::Schedule.current_stage(monthly, Date.new(2026, 3, 31), lead_days: 3).last
    assert_nil Reminders::Schedule.current_stage(bill(due_on: nil), D, lead_days: 3), "no reminder by default"
  end

  test "maintenance next-due follows the same cadence with its own kinds" do
    record = Record.new(next_due_on: D, settled: true)
    assert_equal [ "next_due_today", D ], Reminders::Schedule.next_due_stage(record, D, lead_days: 3)
    assert_equal [ "next_due_final", D + 33 ], Reminders::Schedule.next_due_stage(record, D + 40, lead_days: 3)
  end
end
