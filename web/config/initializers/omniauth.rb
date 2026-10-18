# Google sign-in against the household-signin GCP project (PRD §10). The request phase only accepts
# POST with a CSRF token (omniauth-rails_csrf_protection); AuthHandoffsController starts it.
Rails.application.config.middleware.use OmniAuth::Builder do
  google = Rails.application.credentials.google_sign_in || {}
  provider :google_oauth2, google[:client_id], google[:client_secret], scope: "openid,email,profile", prompt: "select_account"
end

OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.logger = Rails.logger
OmniAuth.config.on_failure = ->(env) { OmniauthCallbacksController.action(:failure).call(env) }
