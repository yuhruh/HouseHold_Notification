# Puts the photos back after the bills. On failure the owner can try again from the restore page.
class DriveRestoreJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Sentry.capture_exception(error)
    DriveBackup.where(id: job.arguments.first).update_all(restore_state: "failed")
  end

  # Declared after retry_on, which would catch this first
  discard_on ActiveRecord::RecordNotFound

  rescue_from DriveBackups::Client::NeedsReconnect do
    DriveBackup.where(id: arguments.first).update_all(restore_state: "failed", problem: "reconnect")
  end

  def perform(backup_id)
    DriveBackups::Restore.call(DriveBackup.find(backup_id))
  end
end
