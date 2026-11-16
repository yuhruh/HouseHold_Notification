# The link from the confirmation email (PRD §10). Having the link isn't enough: an address can be
# typed by anyone, so whoever opens the link must also be the person who asked for it.
# - A new sign-up: the browser that signed up confirms at once (RegistrationsController leaves a
#   cookie); any other browser is asked for the password chosen at sign-up.
# - A changed address: only while signed in to that account.
class EmailConfirmationsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[show update]
  rate_limit to: 10, within: 3.minutes, only: %i[create update], with: -> { redirect_to new_email_confirmation_path, alert: t("auth.rate_limited") }

  def show
    if @user.email_address.present?
      confirm_change
    elsif cookies.encrypted[:signup].to_i == @user.id
      confirm_sign_up
    end # else the page asks for the sign-up password
  end

  # The sign-up password, from a browser other than the one that signed up
  def update
    return redirect_to(email_confirmation_path(params[:token])) if @user.email_address.present?
    return redirect_to(email_confirmation_path(params[:token]), alert: t(".wrong_password")) unless @user.authenticate_password(params[:password].to_s)

    confirm_sign_up
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

  private
    def set_user_by_token
      @user = User.find_by_token_for(:email_confirmation, params[:token])
      redirect_to(new_email_confirmation_path, alert: t("email_confirmations.show.invalid_link")) unless @user
    end

    def confirm_sign_up
      return redirect_to(new_session_path, alert: t("email_confirmations.show.taken")) unless @user.confirm_email!

      cookies.delete(:signup)
      start_new_session_for @user
      redirect_to root_path, notice: t("email_confirmations.show.confirmed")
    end

    # Signed out, the link comes back here after signing in
    def confirm_change
      unless authenticated?
        session[:return_to_after_authenticating] = request.url
        return redirect_to(new_session_path, notice: t("email_confirmations.show.sign_in_first"))
      end
      return redirect_to(root_path, alert: t("email_confirmations.show.other_account")) unless Current.user == @user
      return redirect_to(account_path, alert: t("email_confirmations.show.taken")) unless @user.confirm_email!

      redirect_to account_path, notice: t("email_confirmations.show.changed", email: @user.email_address)
    end
end
