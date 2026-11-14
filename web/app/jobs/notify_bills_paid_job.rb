# After a utility sync marks bills paid (Utilities::BillSync), each member who wants it hears once:
# an inbox item always, a push when pushes are on, and an email when the push can't reach any
# device (pushes off, no device, or every device rejected it). A push no device confirms within
# RECEIPT_WAIT gets the email too (ConfirmPushReceiptsJob). Bills paid together are one message.
class NotifyBillsPaidJob < ApplicationJob
  queue_as :default

  RECEIPT_WAIT = 1.hour
  FORMATTER = Reminders::Wording::FORMATTER

  def perform(household_id, record_ids)
    household = Household.find_by(id: household_id) or return
    records = household.records.where(id: record_ids, settled: true).order(:due_on, :id).to_a
    return if records.empty?

    household.memberships.includes(:user).each do |membership|
      pref = NotificationPreference.for(membership)
      next unless pref.bill_paid

      notify(household, membership.user, pref, records)
    rescue StandardError => e
      Rails.error.report(e, context: { household_id:, user_id: membership.user_id })
    end
  end

  # Sends the fallback email once (here, or when no device confirmed the push)
  def self.email_fallback!(notification)
    user = notification.user
    return if notification.fallback_emailed_at || user.email_address.blank?
    return unless NotificationPreference.for(user.memberships.find_by!(household_id: notification.household_id)).email

    notification.update!(fallback_emailed_at: Time.current)
    BillsPaidMailer.with(notification:, locale: user.locale).paid.deliver_later
  end

  private

  def notify(household, user, pref, records)
    notification = I18n.with_locale(user.locale.presence || I18n.default_locale) do
      Notification.create!(household:, user:, kind: "bills_paid", record_id: (records.first.id if records.one?), **contents(household, records))
    end
    pushed = pref.web_push && push(user, notification)
    self.class.email_fallback!(notification) unless pushed
  end

  def contents(household, records)
    routes = Rails.application.routes.url_helpers
    url = if records.one?
      routes.household_record_path(household, records.first)
    else
      routes.household_records_path(household, status: "paid", category_id: records.map(&:category_id).uniq.one? ? records.first.category_id : nil)
    end
    { title: I18n.t("bills_paid.title", household: household.name, count: records.size),
      body: records.map { line(it) }.join("\n"), url: }
  end

  def line(record)
    parts = [ record.title, record.details.presence, record.period.to_s, FORMATTER.money(record.amount_paid, record.currency) ].compact
    I18n.t("bills_paid.line", bill: parts.join(" · "), paid_on: I18n.l(record.paid_on))
  end

  # true when at least one device's push service accepted it
  def push(user, notification)
    subscriptions = user.push_subscriptions.to_a
    return false if subscriptions.empty?

    payload = { title: notification.title, url: notification.url,
                body: user.push_show_amounts? ? notification.body : I18n.t("bills_paid.generic", locale: user.locale.presence || I18n.default_locale) }
    subscriptions.count { Push::Device.deliver(it, payload, attempts: notification.delivery_attempts, urgency: "normal") }.positive?
  end
end
