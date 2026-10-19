# The daily email digest (PRD §6): each item with its stage, amount and link
class ReminderMailer < ApplicationMailer
  def digest
    @delivery = params[:delivery]
    @household = @delivery.household
    @today = Time.use_zone(@delivery.user.time_zone) { Date.current }
    @logs = @delivery.reminder_logs.includes(:record).order(:id).to_a
    I18n.with_locale(@delivery.user.locale.presence || I18n.default_locale) do
      mail to: @delivery.user.email_address, subject: t("reminders.digest.title", household: @household.name, count: @logs.size)
    end
  end
end
