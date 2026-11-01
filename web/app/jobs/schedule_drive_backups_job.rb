# Sunday mornings (config/recurring.yml). Ledgers that lost Google access wait for Connect Again.
class ScheduleDriveBackupsJob < ApplicationJob
  queue_as :default

  def perform
    DriveBackup.where.not(problem: "reconnect").or(DriveBackup.where(problem: nil)).find_each { |backup| DriveBackupJob.perform_later(backup.id) }
  end
end
