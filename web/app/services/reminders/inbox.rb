module Reminders
  # Writes the in-app copy of a digest (PRD §6: the inbox always receives it)
  module Inbox
    module_function

    def digest!(delivery, today)
      logs = delivery.reminder_logs.includes(:record).order(:id).to_a
      I18n.with_locale(delivery.user.locale.presence || I18n.default_locale) do
        household = delivery.household
        url = if logs.one?
          Rails.application.routes.url_helpers.household_record_path(household, logs.first.record)
        else
          Rails.application.routes.url_helpers.household_upcoming_path(household)
        end
        Notification.create!(household:, user: delivery.user, kind: "reminder_digest", reminder_delivery: delivery,
          title: I18n.t("reminders.digest.title", household: household.name, count: logs.size),
          body: logs.map { |log| Wording.line(log.record, log.kind, today) }.join("\n"),
          url:, record_id: (logs.first.record_id if logs.one?))
      end
    end
  end
end
