# Everything under /h/:household_id (PRD §12a). Non-members get 404, never a hint that the
# household exists; the household comes from the URL, so two tabs never interfere.
module HouseholdScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_household
    after_action :verify_authorized
  end

  private
    def set_household
      Current.membership = Current.user.memberships.includes(:household).find_by!(household_id: params[:household_id])
      Current.household = Current.membership.household
      Current.user.update_column(:last_household_id, Current.household.id) if Current.user.last_household_id != Current.household.id
    end
end
