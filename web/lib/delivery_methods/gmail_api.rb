require "googleauth"
require "google/apis/gmail_v1"

module DeliveryMethods
  # Action Mailer delivery method that sends through the Gmail API (users.messages.send)
  # as the dedicated household sender account. See PRD → "Email via Gmail API".
  #
  # Credentials (Rails credentials):
  #   gmail:
  #     client_id: ...
  #     client_secret: ...
  #     refresh_token: ...   # from `bin/rails gmail:authorize`
  #     sender: household.bills@gmail.com
  class GmailApi
    SCOPE = "https://www.googleapis.com/auth/gmail.send".freeze

    # Raised for a revoked/expired refresh token. Not retryable: someone has to re-run
    # `bin/rails gmail:authorize`.
    class AuthorizationError < StandardError; end

    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      config = self.class.config
      mail.from = config.fetch(:sender) if mail.from.blank?

      service = Google::Apis::GmailV1::GmailService.new
      service.authorization = self.class.credentials(config)
      service.send_user_message("me", upload_source: StringIO.new(mail.to_s), content_type: "message/rfc822")
    rescue Signet::AuthorizationError => e
      raise AuthorizationError, "Gmail authorization failed (#{e.message}). Re-run `bin/rails gmail:authorize`."
    end

    def self.config
      Rails.application.credentials.gmail&.to_h&.symbolize_keys or
        raise ArgumentError, "Missing `gmail` entry in Rails credentials"
    end

    def self.credentials(config)
      Google::Auth::UserRefreshCredentials.new(
        client_id: config.fetch(:client_id),
        client_secret: config.fetch(:client_secret),
        refresh_token: config.fetch(:refresh_token),
        scope: SCOPE
      )
    end
  end
end
