# Bought more: a restock of one supply (and, with the box ticked, a paid Ledger expense). "Log a
# purchase…" first asks what was bought (#pick): the items to buy soon first, then the rest.
#
# One item can be several brands. A scanned barcode no item has yet comes here from New item's "It's
# one of my items": #pick asks which item, and saving the purchase remembers the barcode for it
# (SupplyBarcode.remember), with the product's name, which the next scan fills in.
class Supplies::PurchasesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply, only: %i[new create]
  before_action :set_scan

  def pick
    authorize Supply, :create?
    today = Current.household.today
    supplies = Current.household.supplies.active.includes(:purchases, :counts).order(:name).map { [ it, it.forecast(today:) ] }
    @buy_soon, @others = supplies.partition { it.last.needs_buying? }
  end

  def new
    authorize @supply, :update?
    product = @product_name || (@supply.barcodes.find { it.code == @barcode }&.product_name if @barcode)
    # Filled in from the last time: of this product when a scan says which, so another brand's price
    # isn't offered as this one's (a brand bought for the first time starts with no price)
    last = @supply.latest_purchase
    same = @supply.purchases.select { it.product_name == product }.max_by { [ it.purchased_on, it.created_at ] } if product
    from = same || last
    @purchase = @supply.purchases.new(purchased_on: Current.household.today, quantity: from&.quantity, total_price: (product ? same : last)&.total_price,
                                      store: from&.store, currency: Current.household.default_currency, left_before: @supply.forecast.on_hand_rounded,
                                      product_name: product)
    @scanned_name = @purchase.product_name.present?
  end

  def create
    authorize @supply, :update?
    SupplyPurchase.transaction do
      @purchase = Supplies::LogPurchase.call(@supply, purchase_params, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
      SupplyBarcode.remember(@supply, @barcode, product_name: @purchase.product_name) if @barcode && @purchase.persisted?
    end
    if @purchase.persisted?
      notice = t(@purchase.record ? ".saved_with_ledger" : ".saved", count: @purchase.quantity, unit: t("supplies.units.#{@supply.unit}", count: @purchase.quantity), item: @supply.name)
      redirect_to household_supply_path(Current.household, @supply), notice:, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts, :prices, :barcodes).find(params[:supply_id])
  end

  # From a scan: the barcode, the product's name a lookup found, and whether the barcode is still
  # free to be remembered for the item picked (@link)
  def set_scan
    code = params[:barcode].to_s.gsub(/\D/, "")
    @barcode = code if Supplies::BarcodeLookup.valid?(code)
    @product_name = params[:product_name].to_s.squish.presence
    @link = @barcode.present? && SupplyBarcode.free?(Current.household, @barcode)
  end

  def purchase_params
    params.expect(supply_purchase: %i[quantity total_price store purchased_on expires_on left_before product_name] + Supplies::PaidAmount::KEYS)
  end
end
