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

  # A push that can't reach any device can go by email instead (PRD §6)
  def send_by_email
    authorize ReminderDelivery, :resend?
    delivery = Current.household.reminder_deliveries.failed.web_push.find(params[:id])
    return redirect_to(household_reminder_deliveries_path(Current.household), alert: t("reminder_deliveries.resend.unavailable")) if delivery.user.email_address.blank?

    ReminderMailer.with(delivery:).digest.deliver_later
    delivery.update!(status: "resolved", resent_by: Current.user, resent_at: Time.current, error: t("reminder_deliveries.resend.sent_by_email"))
    redirect_to household_reminder_deliveries_path(Current.household), notice: t("reminder_deliveries.resend.sent_by_email")
  end

  def resend_all
    authorize ReminderDelivery
    Current.household.reminder_deliveries.failed.find_each { |delivery| resend_one(delivery) }
    redirect_to household_reminder_deliveries_path(Current.household), notice: t(".queued")
  end

  helper_method :channel_available?

  private

  def channel_available?(delivery)
    delivery.email? ? delivery.user.email_address.present? : delivery.user.push_subscriptions.exists?
  end

  def resend_one(delivery)
    return t("reminder_deliveries.resend.too_soon") if delivery.resent_at && delivery.resent_at > RESEND_EVERY.ago
    return t("reminder_deliveries.resend.unavailable") unless channel_available?(delivery)

    if Reminders::Resend.remaining_logs(delivery).empty?
      delivery.update!(status: "resolved", error: t("reminder_deliveries.resend.nothing_left"))
      return t("reminder_deliveries.resend.nothing_left")
    end
    delivery.update!(status: "pending", resent_by: Current.user, resent_at: Time.current)
    DeliverReminderJob.perform_later(delivery.id, resend: true)
    t("reminder_deliveries.resend.queued")
  end
end
