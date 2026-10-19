# Monthly (PRD → Backups): photos aren't in the weekly database email, so remind Alex to download
# them with bin/download-photos. Skipped while there are no photos.
class PhotoBackupReminderJob < ApplicationJob
  queue_as :default

  def perform
    count = ActiveStorage::Attachment.where(record_type: "Record", name: "photos").count
    return if count.zero?

    to = ENV["BACKUP_RECIPIENT"].presence || Rails.application.credentials.dig(:gmail, :sender)
    bytes = ActiveStorage::Blob.joins(:attachments).where(active_storage_attachments: { record_type: "Record" }).sum(:byte_size)
    BackupMailer.with(to:, count:, size_mb: (bytes / 1.megabyte.to_f).round(1)).photos_reminder.deliver_now
  end
end
