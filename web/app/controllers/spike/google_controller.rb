module Spike
  # M0 checks X1 (re-auth), X2 (Railway host as redirect) and X10 (non-test users can sign in).
  class GoogleController < BaseController
    def show
      @result = session[:spike_google_result]
    end

    def start
      reauth = params[:mode] == "reauth"
      session[:spike_google] = { "state" => SecureRandom.hex(16), "nonce" => SecureRandom.hex(16),
                                 "reauth" => reauth, "requested_at" => Time.current.to_i }
      redirect_to GoogleOidc.authorization_url(redirect_uri:, reauth:,
        state: session[:spike_google]["state"], nonce: session[:spike_google]["nonce"]), allow_other_host: true
    end

    def callback
      flow = session.delete(:spike_google)
      return redirect_to(spike_google_path, alert: "Google: #{params[:error]}") if params[:error].present?
      return redirect_to(spike_google_path, alert: "State mismatch; start again") unless flow && params[:state] == flow["state"]

      claims = GoogleOidc.exchange(code: params.require(:code), redirect_uri:)
      return redirect_to(spike_google_path, alert: "Nonce mismatch") unless claims["nonce"] == flow["nonce"]

      session[:spike_google_result] = {
        "email" => claims["email"], "email_verified" => claims["email_verified"], "name" => claims["name"],
        "sub" => claims["sub"], "auth_time" => claims["auth_time"], "iat" => claims["iat"],
        "reauth" => flow["reauth"], "requested_at" => flow["requested_at"],
        "fresh_auth" => GoogleOidc.fresh_auth?(claims, flow["requested_at"])
      }
      redirect_to spike_google_path, notice: "Signed in as #{claims['email']}"
    rescue GoogleOidc::Error, Google::Auth::IDTokens::VerificationError => e
      redirect_to spike_google_path, alert: e.message
    end

    private

    def redirect_uri
      "#{request.base_url}/auth/google_oauth2/callback"
    end
  end
end
