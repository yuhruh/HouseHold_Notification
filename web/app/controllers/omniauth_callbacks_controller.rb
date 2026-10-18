class OmniauthCallbacksController < ApplicationController
  include AuthPage

  allow_unauthenticated_access

  def create
    handoff = AuthHandoff.consume(session.delete(:auth_handoff_id))
    return redirect_to(new_session_path, alert: t(".expired")) unless handoff

    # Linking needs the same signed-in user who started the round trip
    linking_user = Current.user if authenticated? && handoff.user_id == Current.user.id
    result = Auth::IdentityResolver.new(request.env["omniauth.auth"], current_user: linking_user, time_zone: handoff.time_zone).call

    case result.status
    when :unverified_email then redirect_to new_session_path, alert: t(".unverified_email")
    when :conflict then redirect_to (linking_user ? root_path : new_session_path), alert: t(".conflict")
    else
      start_new_session_for(result.user) unless linking_user
      redirect_to handoff.return_to || root_path, notice: t(".#{result.status}")
    end
  end

  def failure
    redirect_to new_session_path, alert: t(".failed")
  end
end
