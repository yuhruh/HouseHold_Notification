require "test_helper"

class Auth::CleanupJobTest < ActiveJob::TestCase
  test "deletes 8-day-old unconfirmed users and keeps 6-day-old ones" do
    old = User.create!(unconfirmed_email: "old@example.com", password: "password123", created_at: 8.days.ago)
    recent = User.create!(unconfirmed_email: "recent@example.com", password: "password123", created_at: 6.days.ago)

    Auth::CleanupJob.perform_now

    assert_not User.exists?(old.id)
    assert User.exists?(recent.id)
    assert User.exists?(users(:alex).id)
  end

  test "keeps an old account without email_address that has a Google identity" do
    user = User.create!(created_at: 30.days.ago)
    user.identities.create!(provider: "google_oauth2", uid: "x")
    Auth::CleanupJob.perform_now
    assert User.exists?(user.id)
  end

  test "deletes expired sessions and handoffs" do
    expired = users(:alex).sessions.create!
    expired.update_columns(expires_at: 1.minute.ago)
    active = users(:alex).sessions.create!
    handoff = AuthHandoff.create!(provider: "google_oauth2", time_zone: "Asia/Taipei")
    handoff.update_columns(expires_at: 1.minute.ago)

    Auth::CleanupJob.perform_now

    assert_not Session.exists?(expired.id)
    assert Session.exists?(active.id)
    assert_not AuthHandoff.exists?(handoff.id)
  end
end
