# Add an old price: what an item cost before, for comparing prices only (Price history and Where to
# buy). It never changes the count or the forecast, so it works for something already used up.
class Supplies::PricesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def new
    authorize @supply, :update?
    last = @supply.price_history.first
    @price = @supply.prices.new(product_name: @supply.name, store: last&.store, quantity: last&.quantity, purchased_on: Current.household.today)
  end

  def create
    authorize @supply, :update?
    @price = @supply.prices.new(price_params.merge(household: Current.household, currency: Current.household.default_currency, created_by: Current.user))
    if @price.save
      redirect_to household_supply_path(Current.household, @supply), notice: t(".saved", item: @price.display_name), status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    authorize @supply, :update?
    @supply.prices.find(params[:id]).destroy!
    redirect_to household_supply_path(Current.household, @supply), notice: t(".deleted"), status: :see_other
  end

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :prices).find(params[:supply_id])
  end

  def price_params
    params.expect(supply_price: %i[product_name store quantity total_price purchased_on])
  end
end
