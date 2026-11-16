# The star on an item: owners and co-owners mark a supply a favorite of the whole household (listed on
# Supplies › Favorites) or take the star off. From a list or the item page the star, the item's card or
# row and the Favorites count update in place (Turbo Stream)
class Supplies::FavoritesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def create = mark(true)

  def destroy = mark(false)

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts).find(params[:supply_id])
  end

  def mark(favorite)
    authorize @supply, :update?
    @supply.update!(favorite:)
    @forecast = @supply.forecast
    @favorites = Current.household.supplies.active.favorites.count
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_back_or_to household_supply_path(Current.household, @supply), status: :see_other }
    end
  end
end
