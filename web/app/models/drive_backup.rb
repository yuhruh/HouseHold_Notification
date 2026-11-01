# A household's Google Drive backup, connected by its owner (ADR 0006). The token only reaches files
# the app created (drive.file).
class DriveBackup < ApplicationRecord
  belongs_to :household
  belongs_to :connected_by, class_name: "User"
  has_many :files, class_name: "DriveBackupFile", dependent: :delete_all

  encrypts :refresh_token

  PROBLEMS = %w[reconnect storage_full failed].freeze
  # A run that died with the server leaves running_since behind; this long after, it no longer counts
  STUCK_AFTER = 2.hours

  validates :problem, inclusion: { in: PROBLEMS }, allow_nil: true

  # Off until the Google client and the encryption keys are set (nothing shows in Ledger Settings)
  def self.available?
    [ ENV["GOOGLE_DRIVE_CLIENT_ID"], ENV["GOOGLE_DRIVE_CLIENT_SECRET"], ActiveRecord::Encryption.config.primary_key ].all?(&:present?)
  end

  def running? = running_since.present? && running_since > STUCK_AFTER.ago
  def needs_reconnect? = problem == "reconnect"
  def folder_url = folder_id && "https://drive.google.com/drive/folders/#{folder_id}"
end
