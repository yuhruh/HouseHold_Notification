class EmailConfirmationsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_email_confirmation_path, alert: t("auth.rate_limited") }

  # The link from the confirmation email
  def show
    user = User.find_by_token_for(:email_confirmation, params[:token])
    return redirect_to(new_email_confirmation_path, alert: t(".invalid_link")) unless user
    return redirect_to(new_session_path, alert: t(".taken")) unless user.confirm_email!

    start_new_session_for user
    redirect_to root_path, notice: t(".confirmed")
  end

  # Resend form
  def new
  end

  def create
    email = params[:email_address].to_s.strip.downcase
    locale = I18n.locale.to_s
    if verified = User.find_by(email_address: email)
      AuthMailer.with(user: verified, locale: verified.locale || locale).already_registered.deliver_later
    elsif pending = User.where(email_address: nil, unconfirmed_email: email).order(:created_at).last
      AuthMailer.with(user: pending, locale:).email_confirmation.deliver_later
    end
    redirect_to new_session_path, notice: t(".sent")
  end
end
