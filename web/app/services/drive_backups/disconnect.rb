module DriveBackups
  # Stops the backups and gives up the access. What's already in Drive stays there.
  class Disconnect
    def self.call(household, actor:)
      backup = DriveBackup.find_by(household:) or return
      token = backup.refresh_token
      backup.destroy!
      SecurityEvent.record!("drive_backup_disconnected", actor:, household:)
      # Google revokes the whole account's access, which other ledgers on this account still need
      Oauth.revoke(token) unless DriveBackup.exists?(google_email: backup.google_email)
    end
  end
end
