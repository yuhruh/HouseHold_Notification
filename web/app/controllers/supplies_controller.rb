# Supplies: what the household keeps in stock, how much is left, when it runs out and when to buy
# more (Supplies::Forecast). Everyone sees them; owners and co-owners add, edit and archive.
class SuppliesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply, only: %i[show edit update archive]

  FILTERS = %w[buy_soon expiring].freeze

  def index
    authorize Supply
    supplies = Current.household.supplies.includes(:purchases, :counts)
    supplies = params[:archived].present? ? supplies.where.not(archived_at: nil) : supplies.active
    @today = Current.household.today
    all = supplies.order(:name).map { [ it, it.forecast(today: @today) ] }
    @summary = summary(all)
    @filter = params[:filter].presence_in(FILTERS)
    @kind = params[:kind].presence_in(Supply::KINDS)
    @query = params[:q].to_s.strip
    @kinds_in_use = all.map { it.first.kind }.uniq
    @archived_count = Current.household.supplies.where.not(archived_at: nil).count
    @items = all.select { |supply, forecast| shown?(supply, forecast) }
                .sort_by { |supply, forecast| [ SuppliesHelper::STATUS_ORDER.index(forecast.status), forecast.buy_by || forecast.run_out_on || Date.new(9999), supply.name ] }
  end

  def show
    authorize @supply
    @forecast = @supply.forecast
    @history = @supply.history
    @stores = stores(@supply)
  end

  def new
    authorize Supply
    @supply = Current.household.supplies.new(prefill_params)
    @scan = scan_params
  end

  def create
    authorize Supply
    @supply = Current.household.supplies.new(supply_params.merge(created_by: Current.user, level_at: Time.current))
    @scan = scan_params
    log_purchase = params[:log_purchase] == "1"
    @purchase = SupplyPurchase.new(purchase_params) if log_purchase

    saved = Supply.transaction do
      raise ActiveRecord::Rollback unless @supply.save
      @supply.barcodes.create!(household: Current.household, code: @scan[:barcode]) if @scan[:barcode].present? && !Current.household.supply_barcodes.exists?(code: @scan[:barcode])
      if log_purchase
        @purchase = Supplies::LogPurchase.call(@supply, purchase_params.merge(quantity: @supply.level, left_before: 0, purchased_on: Current.household.today),
                                               user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
        unless @purchase.persisted?
          @supply.errors.add(:base, @purchase.errors.full_messages.to_sentence)
          raise ActiveRecord::Rollback
        end
      else
        Supplies::RecordCount.call(@supply, @supply.level, user: Current.user)
      end
      true
    end

    if saved
      redirect_to household_supply_path(Current.household, @supply), notice: t(".created", item: @supply.name)
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @supply
  end

  def update
    authorize @supply
    if @supply.update(supply_params.except(:level))
      Supplies::StockChanged.call(@supply)
      redirect_to household_supply_path(Current.household, @supply), notice: t(".saved")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Archive hides the item and stops its alerts; its purchases stay in history and the Ledger
  def archive
    authorize @supply
    @supply.update!(archived_at: @supply.archived_at ? nil : Time.current)
    redirect_to household_supplies_path(Current.household), notice: t(@supply.archived_at ? ".archived" : ".restored", item: @supply.name)
  end

  private

  def set_supply
    @supply = Current.household.supplies.includes(:purchases, :counts).find(params[:id])
  end

  def supply_params = params.expect(supply: %i[name kind unit level guess_days_per_unit lead_days alert_when_left])

  def purchase_params
    params.fetch(:purchase, {}).permit(:total_price, :store).to_h.symbolize_keys
  end

  # From a scan: the product name, kind and barcode a lookup found (supplies/scans#barcode)
  def prefill_params
    params.permit(:name, :kind, :unit).to_h.symbolize_keys.tap do |attrs|
      attrs.delete(:kind) unless Supply::KINDS.include?(attrs[:kind])
      attrs.delete(:unit) unless Supply::UNITS.include?(attrs[:unit])
    end
  end

  def scan_params
    params.permit(:barcode, :source, :original_name, :brand, :not_found, filled: []).to_h.symbolize_keys.tap do |scan|
      scan[:barcode] = scan[:barcode].to_s.gsub(/\D/, "").presence
      scan[:filled] = Array(scan[:filled]) & %w[name kind unit]
    end
  end

  def shown?(supply, forecast)
    return false if @filter == "buy_soon" && !forecast.needs_buying?
    return false if @filter == "expiring" && !forecast.expiring?
    return false if @kind && supply.kind != @kind
    return false if @query.present? && !(supply.name.downcase.include?(@query.downcase) || supply.purchases.any? { it.store.to_s.downcase.include?(@query.downcase) })
    true
  end

  # Buy soon, Expiring, an estimated monthly spend (usage × the last price per unit) and the count
  def summary(all)
    monthly = all.sum do |supply, forecast|
      last = supply.latest_purchase
      forecast.enough_data? && last ? forecast.rate * 30 * last.unit_price : 0
    end
    { buy_soon: all.count { it.last.needs_buying? }, expiring: all.count { it.last.expiring? }, monthly:, total: all.size }
  end

  # Where to buy: each store's cheapest price per unit and how often it was used, cheapest first
  def stores(supply)
    supply.purchases.group_by { it.store.presence || "—" }.map do |store, purchases|
      best = purchases.min_by(&:unit_price)
      { store:, best:, times: purchases.size }
    end.sort_by { it[:best].unit_price }
  end
end
