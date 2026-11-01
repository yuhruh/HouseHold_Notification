# Ledger Settings → Google Drive Backup (owner only)
class DriveBackupsController < ApplicationController
  include HouseholdScoped
  include Reauthentication
  before_action { authorize Current.household, :manage? }
  before_action -> { head :not_found unless DriveBackup.available? }
  before_action -> { require_reauthentication("connect_drive_backup", return_to: household_settings_path(Current.household)) }, only: :create

  # Hands over to Google; DriveBackupCallbacksController takes it from there
  def create
    state = SecureRandom.hex(24)
    session[:drive_oauth] = { "state" => state, "household_id" => Current.household.id }
    redirect_to DriveBackups::Oauth.authorization_url(redirect_uri: google_drive_callback_url, state:), allow_other_host: true, status: :see_other
  end

  def run
    backup = Current.household.drive_backup
    DriveBackupJob.perform_later(backup.id) if backup && !backup.running? && !backup.needs_reconnect?
    redirect_to household_settings_path(Current.household), notice: t(".started")
  end

  def destroy
    DriveBackups::Disconnect.call(Current.household, actor: Current.user)
    redirect_to household_settings_path(Current.household), notice: t(".disconnected")
  end
end
