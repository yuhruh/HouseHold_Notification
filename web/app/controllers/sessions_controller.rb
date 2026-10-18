class SessionsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_signed_in_user, only: :new
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("auth.rate_limited") }

  def new
  end

  # Looks up only the verified email_address, so unconfirmed sign-ups can't sign in (PRD §10)
  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t(".invalid")
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end
end
