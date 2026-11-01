module DriveBackups
  # Stops the backups and gives up the access. What's already in Drive stays there.
  class Disconnect
    def self.call(household, actor:)
      backup = DriveBackup.find_by(household:) or return
      token = backup.refresh_token
      backup.destroy!
      SecurityEvent.record!("drive_backup_disconnected", actor:, household:)
      Oauth.revoke(token)
    end
  end
end
