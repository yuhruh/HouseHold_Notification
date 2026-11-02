# Where Google sends the owner back. One fixed URL, so the ledger comes from the session, checked by state.
class DriveBackupCallbacksController < ApplicationController
  def show
    started = session.delete(:drive_oauth) || {}
    return redirect_to(root_path, alert: t(".failed")) unless valid_state?(started)

    household = Current.user.memberships.find_by(household_id: started["household_id"], role: "owner")&.household
    return redirect_to(root_path, alert: t(".failed")) unless household

    settings = household_settings_path(household)
    return redirect_to(settings, alert: t(".failed")) if params[:code].blank?

    token = DriveBackups::Oauth.exchange(code: params[:code], redirect_uri: google_drive_callback_url)
    backup = DriveBackups::Connect.call(household:, user: Current.user, refresh_token: token)
    return redirect_to(settings, notice: t(".connected")).tap { DriveBackupJob.perform_later(backup.id) } if household.records.exists?

    backup.update!(found_backups: DriveBackups::Scan.call(DriveBackups::Client.new(token)))
    redirect_to settings, notice: t(".connected_empty")
  rescue DriveBackups::Oauth::Denied, DriveBackups::Client::NeedsReconnect
    redirect_to settings, alert: t(".failed")
  end

  private

  def valid_state?(started)
    started["state"].present? && ActiveSupport::SecurityUtils.secure_compare(started["state"], params[:state].to_s)
  end
end
