# Password users confirm with their password; Google-only users with an emailed code (PRD §15)
class ReauthenticationsController < ApplicationController
  include AuthPage

  before_action :set_flow
  rate_limit to: 3, within: 10.minutes, only: :code, by: -> { Current.user.id }, with: -> { redirect_to reauthentication_path, alert: t("auth.rate_limited") }
  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { Current.user.id }, with: -> { redirect_to reauthentication_path, alert: t("auth.rate_limited") }

  def show
  end

  def create
    verified = if Current.user.password_set? && params[:password].present?
      Current.user.authenticate_password(params[:password]).present?
    else
      ReauthCode.verify(Current.user, params[:code])
    end
    return redirect_to(reauthentication_path, alert: t(".invalid")) unless verified

    Current.session.update!(reauthenticated_at: Time.current)
    redirect_to session.delete(:reauth)&.dig("return_to") || root_path
  end

  # Emails a code naming the action, so an unexpected one is a warning sign
  def code
    _record, code = ReauthCode.issue!(Current.user, @purpose)
    AuthMailer.with(user: Current.user, code:, purpose: @purpose, locale: Current.user.locale || I18n.locale.to_s).reauth_code.deliver_later
    redirect_to reauthentication_path, notice: t(".sent", email: Current.user.email_address)
  end

  private
    def set_flow
      @purpose = session.dig(:reauth, "purpose").presence_in(ReauthCode::PURPOSES) || "delete_account"
    end
end
