# A photo already in Drive, so the next run skips it
class DriveBackupFile < ApplicationRecord
  belongs_to :drive_backup
end
