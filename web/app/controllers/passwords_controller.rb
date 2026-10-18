class PasswordsController < ApplicationController
  include AuthPage

  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: t("auth.rate_limited") }

  def new
  end

  # Only a verified address can reset; the response is the same either way (PRD §10).
  # A Google-only user sets a first password this way.
  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.with(user:, locale: user.locale || I18n.locale.to_s).reset.deliver_later
    end

    redirect_to new_session_path, notice: t(".sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t(".updated")
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("passwords.invalid_link")
    end
end
