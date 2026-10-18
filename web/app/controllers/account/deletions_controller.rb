module Account
  # /account/deletion: public explanation (also for app-store listings); signed in, the confirmation
  # form behind re-auth (PRD §15)
  class DeletionsController < ApplicationController
    include Reauthentication
    allow_unauthenticated_access only: :show
    before_action -> { require_reauthentication("delete_account") }, only: :show, if: :authenticated?
    before_action -> { require_reauthentication("delete_account", return_to: account_deletion_path) }, only: :create

    def show
      load_households if authenticated?
    end

    def create
      user = Current.user
      email, locale = user.email_address, user.locale || I18n.locale.to_s
      owned_ids = user.memberships.where(role: "owner").pluck(:household_id).map(&:to_s)
      result = Accounts::Delete.call(user:, confirmations: params.fetch(:confirm, {}).permit(*owned_ids).to_h)
      unless result.ok
        load_households
        flash.now[:alert] = t(".blocked")
        return render(:show, status: :unprocessable_content)
      end

      cookies.delete(:session_id)
      AccountMailer.with(email:, locale:).deleted.deliver_later if email
      redirect_to root_path, notice: t(".deleted")
    end

    private
      def load_households
        owned = Current.user.memberships.includes(household: :memberships).select(&:owner?).map(&:household)
        @blocking, @sole = owned.partition { |h| h.memberships.size > 1 }
      end
  end
end
