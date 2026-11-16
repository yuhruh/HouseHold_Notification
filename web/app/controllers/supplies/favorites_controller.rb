# The star on an item: each owner and co-owner adds or takes away their own (SupplyFavorite), and an
# item is on Supplies › Favorites while anyone's star is on it. From a list or the item page the
# star, the item's card or row, the Favorites count and the "Starred by" counts update in place
# (Turbo Stream)
class Supplies::FavoritesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def create
    @supply.favorites.create_or_find_by!(user: Current.user)
    starred
  end

  def destroy
    @supply.favorites.where(user: Current.user).delete_all
    starred
  end

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts).find(params[:supply_id])
    authorize @supply, :update?
  end

  def starred
    @supply.favorites.reset
    @forecast = @supply.forecast
    @supply_starrers = Supplies::Starrers.new(Current.household)
    stars = @supply_starrers.stars
    @favorites = stars.distinct.count(:supply_id)
    @mine = stars.where(user: Current.user).count
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_back_or_to household_supply_path(Current.household, @supply), status: :see_other }
    end
  end
end
