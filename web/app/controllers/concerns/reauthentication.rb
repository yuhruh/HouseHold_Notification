# Sensitive actions need a password check or an emailed code within the last 10 minutes (PRD §15)
module Reauthentication
  extend ActiveSupport::Concern

  private
    # Redirects to the re-auth page and comes back to return_to (a GET page) afterwards
    def require_reauthentication(purpose, return_to: nil)
      return if Current.session.recently_reauthenticated?

      return_to ||= request.get? || request.head? ? request.fullpath : referer_path
      session[:reauth] = { "purpose" => purpose, "return_to" => AuthHandoff.safe_return_to(return_to) || root_path }
      redirect_to reauthentication_path
    end

    def referer_path
      URI(request.referer.to_s).request_uri if request.referer.present?
    rescue URI::InvalidURIError
      nil
    end
end
