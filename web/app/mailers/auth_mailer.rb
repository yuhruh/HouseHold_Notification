class AuthMailer < ApplicationMailer
  # Sent to the pending address after sign-up (or a resend request)
  def email_confirmation
    @user = params[:user]
    @url = email_confirmation_url(@user.generate_token_for(:email_confirmation))
    mail to: @user.unconfirmed_email, subject: t(".subject")
  end

  # Sent instead when someone signs up with an address that already has an account
  def already_registered
    @user = params[:user]
    mail to: @user.email_address, subject: t(".subject")
  end

  # To the old address when an email change is requested
  def email_change_notice
    @user = params[:user]
    mail to: params[:old_email], subject: t(".subject")
  end

  def reauth_code
    @code = params[:code]
    @action = t("reauth_purposes.#{params[:purpose]}")
    mail to: params[:user].email_address, subject: t(".subject", code: @code)
  end
end
