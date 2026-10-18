require "net/http"

module Spike
  # M0 checks X1/X2/X10: a bare OpenID Connect code flow against the sign-in GCP project.
  # Re-auth asks Google for prompt=login + max_age=0 and expects a fresh auth_time back.
  # Replaced by omniauth-google-oauth2 in M1.
  module GoogleOidc
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth".freeze
    TOKEN_URL = URI("https://oauth2.googleapis.com/token")

    class Error < StandardError; end

    module_function

    def config
      Rails.application.credentials.google_sign_in&.to_h&.symbolize_keys or
        raise Error, "Missing `google_sign_in` entry in Rails credentials"
    end

    def authorization_url(redirect_uri:, state:, nonce:, reauth:)
      params = {
        client_id: config.fetch(:client_id), redirect_uri:, response_type: "code",
        scope: "openid email profile", state:, nonce:
      }
      params.merge!(reauth ? { prompt: "login", max_age: 0 } : { prompt: "select_account" })
      "#{AUTH_URL}?#{params.to_query}"
    end

    # Exchanges the code and returns the verified ID token claims.
    def exchange(code:, redirect_uri:)
      response = Net::HTTP.post_form(TOKEN_URL, code:, redirect_uri:, grant_type: "authorization_code",
        client_id: config.fetch(:client_id), client_secret: config.fetch(:client_secret))
      body = JSON.parse(response.body)
      raise Error, "Token exchange failed: #{body['error_description'] || body['error']}" unless response.is_a?(Net::HTTPSuccess)

      Google::Auth::IDTokens.verify_oidc(body.fetch("id_token"), aud: config.fetch(:client_id))
    end

    # X1 passes when Google reports an authentication that happened after the re-auth request.
    def fresh_auth?(claims, requested_at)
      claims["auth_time"].present? && claims["auth_time"].to_i >= requested_at.to_i
    end
  end
end
