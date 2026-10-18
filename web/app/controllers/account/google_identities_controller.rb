module Account
  # Disconnect Google; never the last sign-in method (PRD §10, §13)
  class GoogleIdentitiesController < ApplicationController
    include Reauthentication
    before_action -> { require_reauthentication("disconnect_google", return_to: account_path) }

    def destroy
      return redirect_to(account_path, alert: t(".last_method")) unless Current.user.can_disconnect_google?

      Current.user.google_identity&.destroy!
      SecurityEvent.record!("google_disconnected", user: Current.user, actor: Current.user)
      redirect_to account_path, notice: t(".disconnected")
    end
  end
end
