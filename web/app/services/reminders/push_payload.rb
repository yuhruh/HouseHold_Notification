module Reminders
  # Push text (PRD §6, §13): "我的家：3 筆帳單需要處理", opening the Pending page (or the record
  # when there's one item). With "show amounts" off the body stays generic.
  module PushPayload
    module_function

    def for(delivery)
      user, household = delivery.user, delivery.household
      logs = Resend.remaining_logs(delivery).sort_by(&:id)
      today = Time.use_zone(user.time_zone) { Date.current }
      routes = Rails.application.routes.url_helpers
      I18n.with_locale(user.locale.presence || I18n.default_locale) do
        body = if user.push_show_amounts?
          logs.map { |log| Wording.line(log.record, log.kind, today) }.join("\n")
        else
          I18n.t("reminders.push.generic")
        end
        { title: I18n.t("reminders.digest.title", household: household.name, count: logs.size), body:,
          url: logs.one? ? routes.household_record_path(household, logs.first.record) : routes.household_pending_path(household) }
      end
    end
  end
end
