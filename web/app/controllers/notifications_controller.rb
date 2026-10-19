# The in-app inbox, across the user's households
class NotificationsController < ApplicationController
  def index
    @notifications = Current.user.notifications.includes(:household).order(created_at: :desc).limit(100)
    @unread_ids = @notifications.select { |n| n.read_at.nil? }.map(&:id)
    Current.user.notifications.where(id: @unread_ids).update_all(read_at: Time.current)
  end

  def read_all
    Current.user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
