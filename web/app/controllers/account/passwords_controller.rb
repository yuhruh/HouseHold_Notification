module Account
  # Changing the password needs the current one and signs out every other session (PRD §13)
  class PasswordsController < ApplicationController
    # The current-password check is a password oracle for whoever holds the session; cap guesses per user
    rate_limit to: 5, within: 10.minutes, only: :update, by: -> { Current.user.id }, with: -> { redirect_to account_path, alert: t("auth.rate_limited") }

    def update
      user = Current.user
      return redirect_to(account_path, alert: t(".wrong_password")) unless user.password_set? && user.authenticate_password(params[:current_password].to_s)

      if user.update(params.permit(:password, :password_confirmation))
        user.sessions.where.not(id: Current.session.id).destroy_all
        SecurityEvent.record!("password_changed", user:, actor: user)
        redirect_to account_path, notice: t(".changed")
      else
        redirect_to account_path, alert: user.errors.full_messages.to_sentence
      end
    end
  end
end
