class ApplicationMailer < ActionMailer::Base
  # The Gmail API sends as the authorized sender; the display name is the app's
  default from: -> { email_address_with_name(Rails.application.credentials.dig(:gmail, :sender) || "no-reply@example.com", "Household Tracker") }
  layout "mailer"

  # Mail is rendered in a job, so the caller passes the recipient's locale explicitly
  around_action :use_recipient_locale

  private
    def use_recipient_locale(&)
      I18n.with_locale(params&.dig(:locale).presence || I18n.default_locale, &)
    end
end
