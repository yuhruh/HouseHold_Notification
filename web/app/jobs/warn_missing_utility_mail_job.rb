# Daily at 09:00 Taipei: when 台電's or 台水's bill email is a week later than expected (2 months
# after the last one), the ledger's owner gets a notification (inbox, and a push if they turned
# pushes on) to check the company's app and that the Gmail filter still forwards. Once per missed
# bill.
class WarnMissingUtilityMailJob < ApplicationJob
  queue_as :default

  def perform
    UtilityAccount.where(type: %w[ElectricityAccount WaterAccount]).includes(household: :owner).find_each do |account|
      household = account.household
      today = Time.current.in_time_zone(household.time_zone).to_date
      expected = account.missing_mail_expected_on(today)
      next if expected.nil? || account.missing_mail_warned_for == expected

      warn(account, expected)
      account.update!(missing_mail_warned_for: expected)
    rescue StandardError => e
      Rails.error.report(e, context: { utility_account_id: account.id })
    end
  end

  private

  def warn(account, expected)
    household, owner = account.household, account.household.owner
    return unless owner

    I18n.with_locale(owner.locale.presence || I18n.default_locale) do
      last = account.last_mail_on
      scope = "#{account.model_name.plural}.missing_mail"
      title = I18n.t("#{scope}.title", household: household.name)
      body = I18n.t(last ? "#{scope}.body" : "#{scope}.body_first",
        expected: I18n.l(expected), last: last && I18n.l(last), since: I18n.l(account.created_at.in_time_zone(household.time_zone).to_date))
      url = Rails.application.routes.url_helpers.public_send("household_#{account.model_name.singular}_path", household)
      Notification.create!(household:, user: owner, kind: "utility_mail_missing", title:, body:, url:)
      WebPushNotifier.notify(owner, title:, body:, url:) if NotificationPreference.for(household.owner_membership).web_push
    end
  end
end
