# My Account → Notifications: per-household channel toggles (PRD §13)
class Account::NotificationPreferencesController < ApplicationController
  def update
    membership = Current.user.memberships.find_by!(household_id: params[:household_id])
    NotificationPreference.for(membership).update!(params.expect(notification_preference: %i[email web_push]))
    redirect_to account_path(anchor: "notifications"), notice: t(".saved")
  end
end
