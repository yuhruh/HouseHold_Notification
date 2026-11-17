# Edit › Combine another item into this one: the item being edited ("Shampoo") is kept, and another
# item, saved for one product ("Promise Volume Shampoo"), moves into it and becomes a brand of it
# (Supplies::Combine). #new asks which item, the ones in the same category first; each choice asks
# to confirm, since it can't be undone.
class Supplies::CombinesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def new
    @same, @others = others.includes(:category).order(:name).partition { it.supply_category_id == @supply.supply_category_id }
  end

  def create
    other = others.find(params[:from])
    Supplies::Combine.call(other, into: @supply, user: Current.user)
    redirect_to household_supply_path(Current.household, @supply), notice: t(".combined", item: other.name, target: @supply.name), status: :see_other
  end

  private

  def set_supply
    @supply = Current.household.supplies.find(params[:supply_id])
    authorize @supply, :combine?
  end

  # Any other item still in use, whatever its unit: the count keeps the unit of the item kept
  def others = Current.household.supplies.active.where.not(id: @supply.id)
end
