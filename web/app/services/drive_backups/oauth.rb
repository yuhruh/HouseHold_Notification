module DriveBackups
  # The owner's consent for Drive. Separate from Google sign-in, which keeps its basic scopes.
  module Oauth
    SCOPE = "https://www.googleapis.com/auth/drive.file".freeze
    REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze

    Denied = Class.new(StandardError)

    def self.authorization_url(redirect_uri:, state:)
      client(redirect_uri:).authorization_uri(state:, access_type: "offline", prompt: "consent").to_s
    end

    # The refresh token for a code from the callback
    def self.exchange(code:, redirect_uri:)
      google = client(redirect_uri:)
      google.code = code
      token = google.fetch_access_token!
      # Signet renames Google's "scope" to this. Unticking Drive on the consent screen leaves it out.
      raise Denied unless token["refresh_token"].present? && token["granted_scopes"].to_s.split.include?(SCOPE)

      token["refresh_token"]
    rescue Signet::AuthorizationError => e
      Rails.logger.warn("Drive token exchange refused: #{e.message}")
      raise Denied
    end

    # Best effort: the token is already gone from here, and the owner can also remove access in Google
    def self.revoke(token)
      Net::HTTP.start("oauth2.googleapis.com", 443, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        http.post(URI(REVOKE_URL).path, URI.encode_www_form(token:), "Content-Type" => "application/x-www-form-urlencoded")
      end
    rescue StandardError => e
      Rails.logger.warn("Drive token revoke failed: #{e.class}")
    end

    def self.client(redirect_uri:)
      Signet::OAuth2::Client.new(
        authorization_uri: "https://accounts.google.com/o/oauth2/v2/auth", token_credential_uri: "https://oauth2.googleapis.com/token",
        client_id: ENV["GOOGLE_DRIVE_CLIENT_ID"], client_secret: ENV["GOOGLE_DRIVE_CLIENT_SECRET"], scope: SCOPE, redirect_uri:
      )
    end
    private_class_method :client
  end
end
