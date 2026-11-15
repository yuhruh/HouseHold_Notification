# Daily, 09:00 Taipei: each household's supplies digest (Supplies::Alerts) to every member who
# wants it (supply_alert; on for owners and co-owners, off for viewers): an inbox item always, a
# push when pushes are on, and an email when the push can't reach any device. A push no device
# confirms within RECEIPT_WAIT gets the email too (ConfirmPushReceiptsJob). One message per
# household per day, however many items it lists.
class SupplyAlertsJob < ApplicationJob
  queue_as :default

  RECEIPT_WAIT = NotifyBillsPaidJob::RECEIPT_WAIT

  def perform
    Household.where(id: Supply.active.select(:household_id)).find_each do |household|
      lines = Supplies::Alerts.call(household)
      next if lines.empty?

      household.memberships.includes(:user).each do |membership|
        pref = NotificationPreference.for(membership)
        next unless pref.supply_alert

        notify(household, membership.user, pref, lines)
      rescue StandardError => e
        Rails.error.report(e, context: { household_id: household.id, user_id: membership.user_id })
      end
    rescue StandardError => e
      Rails.error.report(e, context: { household_id: household.id })
    end
  end

  # Sends the fallback email once (here, or when no device confirmed the push)
  def self.email_fallback!(notification)
    user = notification.user
    return if notification.fallback_emailed_at || user.email_address.blank?
    return unless NotificationPreference.for(user.memberships.find_by!(household_id: notification.household_id)).email

    notification.update!(fallback_emailed_at: Time.current)
    SupplyAlertsMailer.with(notification:, locale: user.locale).digest.deliver_later
  end

  private

  def notify(household, user, pref, lines)
    notification = I18n.with_locale(user.locale.presence || I18n.default_locale) do
      Notification.create!(household:, user:, kind: "supplies",
        title: I18n.t("supplies.alerts.title", household: household.name, count: lines.size),
        body: lines.map(&:text).join("\n"),
        url: Rails.application.routes.url_helpers.household_supplies_path(household))
    end
    pushed = pref.web_push && push(user, notification)
    self.class.email_fallback!(notification) unless pushed
  end

  # true when at least one device's push service accepted it
  def push(user, notification)
    subscriptions = user.push_subscriptions.to_a
    return false if subscriptions.empty?

    body = user.push_show_amounts? ? notification.body : I18n.t("supplies.alerts.generic", locale: user.locale.presence || I18n.default_locale)
    payload = { title: notification.title, url: notification.url, body: }
    subscriptions.count { Push::Device.deliver(it, payload, attempts: notification.delivery_attempts, urgency: "normal") }.positive?
  end
end
