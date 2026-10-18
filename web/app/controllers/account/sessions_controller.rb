module Account
  class SessionsController < ApplicationController
    # "Sign out other sessions"
    def destroy
      Current.user.sessions.where.not(id: Current.session.id).destroy_all
      SecurityEvent.record!("sessions_revoked", user: Current.user, actor: Current.user)
      redirect_to account_path, notice: t(".done")
    end
  end
end
