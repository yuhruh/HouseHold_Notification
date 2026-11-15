# Bought more: a restock of one supply (and, with the box ticked, a paid Ledger expense). "Log a
# purchase…" first asks what was bought (#pick): the items to buy soon first, then the rest.
class Supplies::PurchasesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply, only: %i[new create]

  def pick
    authorize Supply, :create?
    today = Current.household.today
    supplies = Current.household.supplies.active.includes(:purchases, :counts).order(:name).map { [ it, it.forecast(today:) ] }
    @buy_soon, @others = supplies.partition { it.last.needs_buying? }
  end

  def new
    authorize @supply, :update?
    last = @supply.latest_purchase
    @purchase = @supply.purchases.new(purchased_on: Current.household.today, quantity: last&.quantity, total_price: last&.total_price,
                                      store: last&.store, currency: Current.household.default_currency, left_before: @supply.forecast.on_hand_rounded)
    @purchase.total_price = nil if params[:scan].present? && last.nil?
  end

  def create
    authorize @supply, :update?
    @purchase = Supplies::LogPurchase.call(@supply, purchase_params, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
    if @purchase.persisted?
      notice = t(@purchase.record ? ".saved_with_ledger" : ".saved", count: @purchase.quantity, unit: t("supplies.units.#{@supply.unit}", count: @purchase.quantity), item: @supply.name)
      redirect_to household_supply_path(Current.household, @supply), notice:, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts).find(params[:supply_id])
  end

  def purchase_params
    params.expect(supply_purchase: %i[quantity total_price store purchased_on expires_on left_before])
  end
end
