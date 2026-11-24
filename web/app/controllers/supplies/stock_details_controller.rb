# "Add details" for stock counted before any purchase was logged (Supplies::AddStockDetails), from
# "No purchase logged" on the item page. With old prices in Price history from on or before the day
# it was counted, two or more are listed to choose from (or "None of these") and one is shown to
# confirm (or "No, enter the details"); with none, or asked to, the details are typed in, the price
# optional. "Also add to Ledger" is offered once there is a price.
class Supplies::StockDetailsController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def new
    authorize @supply, :update?
    return gone unless @details.batch

    @entering = params[:enter] == "1" || @details.choices.empty?
    if @entering
      @purchase = @supply.purchases.new(purchased_on: @details.last_day, quantity: @details.counted_left, product_name: @details.batch.product.presence,
                                        currency: Current.household.default_currency)
    else
      @price = @details.choices.find { it.id.to_s == params[:price_id].to_s } || @details.choices.first
      @purchase = @supply.purchases.new(quantity: @price.quantity)
    end
  end

  def create
    authorize @supply, :update?
    return gone unless @details.batch

    add_to_ledger = params[:add_to_ledger] == "1"
    if params[:price_id].present?
      @price = @details.choices.find { it.id.to_s == params[:price_id].to_s }
      return gone unless @price
      given = params.fetch(:supply_purchase, {}).permit(:quantity, :expires_on)
      @purchase = @details.from_price(@price, quantity: given[:quantity], expires_on: given[:expires_on], user: Current.user, add_to_ledger:)
    else
      @entering = true
      @purchase = @details.entered(purchase_params, user: Current.user, add_to_ledger:)
    end

    if @purchase.persisted?
      notice = t(".saved", amount: helpers.supply_count(@supply, @details.batch.left), item: @supply.name)
      redirect_to household_supply_path(Current.household, @supply), notice:, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts, :prices).find(params[:supply_id])
    @details = Supplies::AddStockDetails.new(@supply)
  end

  # It has its purchase already (another tab, or someone else), or the old price was deleted
  def gone
    redirect_to household_supply_path(Current.household, @supply), alert: t("supplies.stock_details.gone"), status: :see_other
  end

  def purchase_params
    params.expect(supply_purchase: %i[purchased_on quantity expires_on product_name store total_price] + Supplies::PaidAmount::KEYS)
  end
end
