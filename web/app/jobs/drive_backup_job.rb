# One ledger's backup. Google's hiccups are retried; a problem the owner has to fix is shown in Ledger
# Settings and sent to them once.
class DriveBackupJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Sentry.capture_exception(error)
    backup = DriveBackup.find_by(id: job.arguments.first)
    job.send(:report, backup, "failed") if backup
  end

  # Declared after retry_on, which would catch these first
  # Disconnected or the ledger deleted during the run
  discard_on ActiveRecord::RecordNotFound, ActiveRecord::InvalidForeignKey

  rescue_from DriveBackups::Client::NeedsReconnect do
    report(DriveBackup.find_by(id: arguments.first), "reconnect")
  end

  rescue_from DriveBackups::Client::StorageFull do
    report(DriveBackup.find_by(id: arguments.first), "storage_full")
  end

  def perform(backup_id)
    DriveBackups::Run.call(DriveBackup.find(backup_id))
  end

  private

  def report(backup, problem)
    return if backup.nil? || backup.problem == problem

    backup.update!(problem:)
    household, owner = backup.household, backup.household.owner
    I18n.with_locale(owner.locale.presence || I18n.default_locale) do
      title = I18n.t("drive_backups.notification.title", household: household.name)
      body = I18n.t("drive_backups.problems.#{problem}")
      url = Rails.application.routes.url_helpers.household_settings_path(household)
      Notification.create!(household:, user: owner, kind: "drive_backup_failed", title:, body:, url:)
      WebPushNotifier.notify(owner, title:, body:, url:) if NotificationPreference.for(household.owner_membership).web_push
    end
  end
end
