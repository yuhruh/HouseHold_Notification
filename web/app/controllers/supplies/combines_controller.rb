# Edit › Combine with another item: an item saved once per product ("Promise Volume Shampoo") moves
# into the item it really is ("Shampoo") and becomes a brand of it (Supplies::Combine). #new asks
# which item, the ones in the same category first; each choice asks to confirm, since it can't be
# undone.
class Supplies::CombinesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def new
    @same, @others = targets.includes(:category).order(:name).partition { it.supply_category_id == @supply.supply_category_id }
  end

  def create
    target = targets.find(params[:into])
    Supplies::Combine.call(@supply, into: target, user: Current.user)
    redirect_to household_supply_path(Current.household, target), notice: t(".combined", item: @supply.name, target: target.name), status: :see_other
  end

  private

  def set_supply
    @supply = Current.household.supplies.find(params[:supply_id])
    authorize @supply, :combine?
  end

  # Any other item still in use, whatever its unit: the count keeps the unit of the one picked
  def targets = Current.household.supplies.active.where.not(id: @supply.id)
end
