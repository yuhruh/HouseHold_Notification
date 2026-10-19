# Once a day per household, after the owner's reminder hour (PRD §6): one summary of every failed
# delivery the owner hasn't been told about, in-app always and by email unless email is what
# failed. Also pings the delivery-health heartbeat (DELIVERY_HEALTH_HEARTBEAT_URL): success when
# nothing failed since the last summary, /fail when something did. Enqueued after each reminder run.
class OwnerFailureSummaryJob < ApplicationJob
  queue_as :default

  def perform
    Household.includes(:owner).find_each { |household| summarize(household) }
  end

  private

  def summarize(household)
    owner = household.owner or return
    Time.use_zone(owner.time_zone) do
      now = Time.current
      today = now.to_date
      return if now.hour < owner.reminder_hour
      return if household.last_failure_summary_on && household.last_failure_summary_on >= today

      failed = ReminderDelivery.failed.where(household:, owner_notified_at: nil).includes(:user).order(:id).to_a
      Household.transaction do
        notify(household, owner, failed) if failed.any?
        ReminderDelivery.where(id: failed.map(&:id)).update_all(owner_notified_at: now)
        household.update_columns(last_failure_summary_on: today)
      end
      Heartbeat.ping(ENV["DELIVERY_HEALTH_HEARTBEAT_URL"], failed.any? ? "/fail" : "")
    end
  end

  def notify(household, owner, failed)
    I18n.with_locale(owner.locale.presence || I18n.default_locale) do
      lines = failed.map { |d| I18n.t("reminder_deliveries.summary.line", member: d.user.display_name.presence || d.user.email_address, channel: I18n.t("reminder_deliveries.channels.#{d.channel}"), error: d.error.presence || "–") }
      title = I18n.t("reminder_deliveries.summary.title", household: household.name, count: failed.size)
      url = Rails.application.routes.url_helpers.household_reminder_deliveries_path(household)
      Notification.create!(household:, user: owner, kind: "delivery_failed", title:, body: lines.join("\n"), url:)
      return if failed.any?(&:email?) || owner.email_address.blank?

      OwnerSummaryMailer.with(household:, owner:, title:, lines:).summary.deliver_later
    end
  end
end
