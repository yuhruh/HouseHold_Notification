# Sign-in, sign-up and recovery pages: links on them must not leak tokens through Referer (PRD §10).
module AuthPage
  extend ActiveSupport::Concern

  included do
    after_action { response.set_header("Referrer-Policy", "no-referrer") }
  end

  private
    def redirect_signed_in_user
      redirect_to root_path if authenticated?
    end
end
