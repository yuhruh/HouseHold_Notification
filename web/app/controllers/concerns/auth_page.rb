# Sign-in, sign-up and recovery pages: links on them must not leak tokens through Referer (PRD §10).
# "same-origin" sends Referer to this app only, never to another site. Not "no-referrer": with it a
# browser sends "Origin: null" on a plain (non-Turbo) form post, which Rails' CSRF check rejects, so
# Continue with Google and the theme buttons on these pages answered 422.
module AuthPage
  extend ActiveSupport::Concern

  included do
    after_action { response.set_header("Referrer-Policy", "same-origin") }
  end

  private
    def redirect_signed_in_user
      redirect_to root_path if authenticated?
    end
end
