class HouseholdDeletionsController < ApplicationController
  include HouseholdScoped
  include Reauthentication
  before_action { authorize Current.household, :manage? }
  before_action -> { require_reauthentication("delete_household") }, only: :new
  before_action -> { require_reauthentication("delete_household", return_to: new_household_deletion_path(Current.household)) }, only: :create

  def new
  end

  # The owner types the household name to confirm
  def create
    return redirect_to(new_household_deletion_path(Current.household), alert: t(".name_mismatch")) unless params[:confirm_name].to_s.strip == Current.household.name

    name = Current.household.name
    Households::Purge.call(Current.household, actor: Current.user)
    redirect_to root_path, notice: t(".deleted", name:)
  end
end
