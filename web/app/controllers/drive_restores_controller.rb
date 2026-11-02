# Restoring an empty ledger from a backup found in the owner's Google Drive
class DriveRestoresController < ApplicationController
  include HouseholdScoped
  include Reauthentication
  before_action { authorize Current.household, :manage? }
  before_action :set_backup
  before_action -> { require_reauthentication("restore_drive_backup", return_to: household_drive_restore_path(Current.household, folder: params[:folder])) }, only: :create

  # Step 2, then progress and the result on the same page
  def show
    return if @backup.restore_state

    @found = @backup.found(params[:folder]) or return redirect_to(settings, alert: t(".gone"))
    return redirect_to(settings, alert: t(".not_empty")) if Current.household.records.exists?

    @plan = DriveBackups::Restore.plan(@backup, @found)
  end

  def create
    found = @backup.found(params[:folder]) or return redirect_to(settings, alert: t("drive_restores.show.gone"))
    return redirect_to(settings, alert: t("drive_restores.show.not_empty")) if Current.household.records.exists?

    Imports::Commit.call(Current.household.import_previews.pending.find(params[:preview_id]), user: Current.user)
    @backup.update!(folder_id: found["folder_id"], csv_file_id: found["csv_id"], restore_state: "running", restore_bills: found["bills"], found_backups: [])
    DriveRestoreJob.perform_later(@backup.id)
    redirect_to household_drive_restore_path(Current.household)
  rescue Imports::Commit::Aborted
    redirect_to household_drive_restore_path(Current.household, folder: params[:folder]), alert: t(".failed")
  end

  def resume
    @backup.update!(restore_state: "running") unless @backup.restoring?
    DriveRestoreJob.perform_later(@backup.id)
    redirect_to household_drive_restore_path(Current.household)
  end

  # Start Fresh: leave the old backup alone. The next backup makes a new folder.
  def destroy
    @backup.update!(found_backups: [])
    redirect_to settings
  end

  private

  def set_backup
    @backup = Current.household.drive_backup or redirect_to(settings)
  end

  def settings = household_settings_path(Current.household)
end
