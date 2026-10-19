# The owner removes a member's device, e.g. a lost phone whose session already expired (PRD §14)
class MemberDevicesController < ApplicationController
  include HouseholdScoped

  def destroy
    authorize Current.household, :manage_members?
    member_ids = Current.household.memberships.select(:user_id)
    PushSubscription.where(user_id: member_ids).find(params[:id]).destroy!
    redirect_to household_members_path(Current.household), notice: t("push_subscriptions.destroy.removed")
  end
end
