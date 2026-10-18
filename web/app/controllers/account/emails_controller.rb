# Email change: the new address waits in unconfirmed_email until its link is opened; the old one is told
module Account
  class EmailsController < ApplicationController
    include Reauthentication
    before_action -> { require_reauthentication("change_email", return_to: account_path) }, unless: -> { Current.user.password_set? }
    rate_limit to: 5, within: 10.minutes, only: %i[update resend], by: -> { Current.user.id }, with: -> { redirect_to account_path, alert: t("auth.rate_limited") }

    def update
      user = Current.user
      if user.password_set? && !user.authenticate_password(params[:current_password].to_s)
        return redirect_to(account_path, alert: t(".wrong_password"))
      end

      new_email = params[:email_address].to_s.strip.downcase
      return redirect_to(account_path, alert: t(".same")) if new_email == user.email_address

      user.unconfirmed_email = new_email
      return redirect_to(account_path, alert: user.errors.full_messages.to_sentence) unless user.save

      locale = user.locale || I18n.locale.to_s
      AuthMailer.with(user:, locale:).email_confirmation.deliver_later
      AuthMailer.with(user:, locale:, old_email: user.email_address).email_change_notice.deliver_later
      SecurityEvent.record!("email_change_requested", user:, actor: user)
      redirect_to account_path, notice: t(".pending", email: new_email)
    end

    def resend
      AuthMailer.with(user: Current.user, locale: Current.user.locale || I18n.locale.to_s).email_confirmation.deliver_later if Current.user.unconfirmed_email
      redirect_to account_path, notice: t(".resent")
    end

    def destroy
      Current.user.update!(unconfirmed_email: nil)
      redirect_to account_path, notice: t(".cancelled")
    end
  end
end
