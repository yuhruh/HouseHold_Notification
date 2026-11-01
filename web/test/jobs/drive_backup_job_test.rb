require "test_helper"

class DriveBackupJobTest < ActiveJob::TestCase
  setup do
    @home = households(:home)
    @backup = DriveBackup.create!(household: @home, connected_by: users(:alex), google_email: "alex@example.com", refresh_token: "token")
  end

  def perform_failing(error)
    with_stub(DriveBackups::Run, :call, ->(*) { raise error }) { DriveBackupJob.perform_now(@backup.id) }
  end

  test "lost Google access asks the owner to connect again, once" do
    assert_difference -> { Notification.where(kind: "drive_backup_failed", user: @home.owner).count }, 1 do
      2.times { perform_failing(DriveBackups::Client::NeedsReconnect.new) }
    end
    assert_equal "reconnect", @backup.reload.problem
  end

  test "a full Drive is shown to the owner" do
    perform_failing(DriveBackups::Client::StorageFull.new)
    assert_equal "storage_full", @backup.reload.problem
  end

  test "other errors retry, not reporting yet" do
    assert_enqueued_with(job: DriveBackupJob) { perform_failing(RuntimeError.new("Google hiccup")) }
    assert_nil @backup.reload.problem
  end

  test "a run ending because of a disconnect is dropped quietly" do
    assert_nothing_raised { with_stub(DriveBackups::Run, :call, ->(*) { raise ActiveRecord::RecordNotFound }) { DriveBackupJob.perform_now(@backup.id) } }
  end

  test "Sunday's schedule skips ledgers waiting to reconnect" do
    assert_enqueued_jobs(1, only: DriveBackupJob) { ScheduleDriveBackupsJob.perform_now }
    @backup.update!(problem: "failed")
    assert_enqueued_jobs(1, only: DriveBackupJob) { ScheduleDriveBackupsJob.perform_now }
    @backup.update!(problem: "reconnect")
    assert_no_enqueued_jobs(only: DriveBackupJob) { ScheduleDriveBackupsJob.perform_now }
  end
end
