module Account
  # Changing the password needs the current one and signs out every other session (PRD §13)
  class PasswordsController < ApplicationController
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
