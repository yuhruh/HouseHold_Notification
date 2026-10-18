# "Continue with Google": stores tz/return_to server-side, then re-POSTs (307, same form body and
# CSRF token) to the OmniAuth request phase. Only the handoff id rides in the session (PRD §10).
class AuthHandoffsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, with: -> { redirect_to new_session_path, alert: t("auth.rate_limited") }

  def create
    handoff = AuthHandoff.create!(provider: "google_oauth2", time_zone: User.valid_time_zone(params[:tz]),
      return_to: AuthHandoff.safe_return_to(params[:return_to]), user: (Current.user if authenticated?))
    session[:auth_handoff_id] = handoff.id
    redirect_to "/auth/google_oauth2", status: :temporary_redirect
  end
end
