module DriveBackups
  # Saves the owner's Drive access. Connecting a different Google account starts over: nothing the
  # app put in the old account can be reached from the new one.
  class Connect
    def self.call(household:, user:, refresh_token:, client: Client.new(refresh_token))
      email = client.email
      backup = DriveBackup.find_or_initialize_by(household:)
      backup.transaction do
        if backup.persisted? && backup.google_email != email
          backup.files.delete_all
          backup.assign_attributes(folder_id: nil, csv_file_id: nil, folders: {}, bills_count: 0, photos_count: 0, last_backup_at: nil)
        end
        backup.update!(connected_by: user, google_email: email, refresh_token:, problem: nil)
        SecurityEvent.record!("drive_backup_connected", actor: user, household:)
      end
      backup
    end
  end
end
