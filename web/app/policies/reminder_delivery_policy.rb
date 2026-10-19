# The delivery status page and resend are owner-only (PRD §6)
class ReminderDeliveryPolicy < ApplicationPolicy
  def index? = membership&.owner? || false
  alias_method :resend?, :index?
  alias_method :resend_all?, :index?
  alias_method :send_by_email?, :index?
end
