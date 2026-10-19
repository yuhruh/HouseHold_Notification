# Household settings → Reminder delivery (owner only, PRD §6): failed digests with reasons, and
# Resend (one per delivery per 10 minutes), rebuilt from the items that are still unpaid.
class ReminderDeliveriesController < ApplicationController
  include HouseholdScoped
  RESEND_EVERY = 10.minutes
  STREAK = 3

  def index
    authorize ReminderDelivery
    @failed = Current.household.reminder_deliveries.failed.includes(:user, :delivery_attempts, reminder_logs: :record).order(id: :desc).limit(100)
    recent = Current.household.reminder_deliveries.where.not(channel: "in_app").order(run_on: :desc, id: :desc)
      .group_by { |d| [ d.user_id, d.channel ] }
    @streaks = recent.select { |_, list| list.first(STREAK).size == STREAK && list.first(STREAK).all?(&:failed?) }.keys
  end

  def resend
    authorize ReminderDelivery
    delivery = Current.household.reminder_deliveries.failed.find(params[:id])
    notice = resend_one(delivery)
    redirect_to household_reminder_deliveries_path(Current.household), notice:
  end

  def resend_all
    authorize ReminderDelivery
    Current.household.reminder_deliveries.failed.find_each { |delivery| resend_one(delivery) }
    redirect_to household_reminder_deliveries_path(Current.household), notice: t(".queued")
  end

  private

  def resend_one(delivery)
    return t("reminder_deliveries.resend.too_soon") if delivery.resent_at && delivery.resent_at > RESEND_EVERY.ago
    return t("reminder_deliveries.resend.unavailable") unless delivery.email? && delivery.user.email_address.present?

    if Reminders::Resend.remaining_logs(delivery).empty?
      delivery.update!(status: "resolved", error: t("reminder_deliveries.resend.nothing_left"))
      return t("reminder_deliveries.resend.nothing_left")
    end
    delivery.update!(status: "pending", resent_by: Current.user, resent_at: Time.current)
    DeliverReminderJob.perform_later(delivery.id, resend: true)
    t("reminder_deliveries.resend.queued")
  end
end
