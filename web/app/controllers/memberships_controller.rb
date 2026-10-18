# Owner changes roles (co_owner ↔ viewer) and removes members; anyone but the owner can leave (PRD §12, §14)
class MembershipsController < ApplicationController
  include HouseholdScoped
  before_action :set_membership, only: %i[update destroy]

  def update
    authorize Current.household, :manage_members?
    role = params.expect(membership: [ :role ])[:role]
    return head(:unprocessable_content) unless %w[co_owner viewer].include?(role) && !@membership.owner?

    @membership.update!(role:)
    SecurityEvent.record!("role_changed", actor: Current.user, user: @membership.user, household: Current.household, role:)
    redirect_to household_members_path(Current.household), notice: t(".updated")
  end

  def destroy
    authorize Current.household, :manage_members?
    return head(:unprocessable_content) if @membership.owner?

    remove(@membership, "member_removed")
    redirect_to household_members_path(Current.household), notice: t(".removed")
  end

  def leave
    authorize Current.household, :show?
    return redirect_to(household_members_path(Current.household), alert: t(".owner_cannot_leave")) if Current.membership.owner?

    remove(Current.membership, "member_left")
    redirect_to root_path, notice: t(".left", household: Current.household.name)
  end

  private
    def set_membership
      @membership = Current.household.memberships.find(params[:id])
    end

    def remove(membership, kind)
      membership.destroy!
      membership.user.update_column(:last_household_id, nil) if membership.user.last_household_id == Current.household.id
      SecurityEvent.record!(kind, actor: Current.user, user: membership.user, household: Current.household)
    end
end
