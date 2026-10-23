module Reminders
  # Writes the in-app copy of a digest (PRD §6: the inbox always receives it)
  module Inbox
    module_function

    def digest!(delivery, today)
      logs = delivery.reminder_logs.includes(:record).order(:id).to_a
      Notification.create!(household: delivery.household, user: delivery.user, kind: "reminder_digest", reminder_delivery: delivery,
        **contents(delivery, logs, today))
    end

    # A deleted bill leaves the inbox: a digest about only that bill goes, and a digest that listed
    # others is rewritten without it (worded as on the day it was sent). Call before destroying it.
    def forget!(record)
      deliveries = ReminderLog.where(record_id: record.id).where.not(reminder_delivery_id: nil).select(:reminder_delivery_id)
      Notification.where(kind: "reminder_digest", reminder_delivery_id: deliveries).includes(:reminder_delivery).find_each do |note|
        delivery = note.reminder_delivery
        logs = delivery.reminder_logs.where.not(record_id: record.id).includes(:record).order(:id).to_a
        logs.empty? ? note.destroy! : note.update!(contents(delivery, logs, delivery.run_on))
      end
    end

    def contents(delivery, logs, today)
      I18n.with_locale(delivery.user.locale.presence || I18n.default_locale) do
        household = delivery.household
        url = if logs.one?
          Rails.application.routes.url_helpers.household_record_path(household, logs.first.record)
        else
          Rails.application.routes.url_helpers.household_pending_path(household)
        end
        { title: I18n.t("reminders.digest.title", household: household.name, count: logs.size),
          body: logs.map { |log| Wording.line(log.record, log.kind, today) }.join("\n"),
          url:, record_id: (logs.first.record_id if logs.one?) }
      end
    end
  end
end
