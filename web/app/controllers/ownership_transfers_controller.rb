class OwnershipTransfersController < ApplicationController
  include HouseholdScoped
  include Reauthentication
  before_action { authorize Current.household, :manage? }
  before_action -> { require_reauthentication("transfer_ownership") }, only: :new
  before_action -> { require_reauthentication("transfer_ownership", return_to: new_household_ownership_transfer_path(Current.household)) }, only: :create

  def new
    @candidates = Current.household.memberships.includes(:user).where.not(user: Current.user)
  end

  def create
    target = Current.household.memberships.find(params[:membership_id])
    Accounts::OwnershipTransfer.call(household: Current.household, from: Current.user, to_membership: target)
    redirect_to household_members_path(Current.household), notice: t(".done", name: target.user.display_name.presence || target.user.email_address)
  rescue Accounts::OwnershipTransfer::NotAllowed
    head :forbidden
  end
end
