# Supplies: what the household keeps in stock, how much is left, when it runs out and when to buy
# more (Supplies::Forecast). Everyone sees them; owners and co-owners add, edit and archive.
class SuppliesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply, only: %i[show edit update archive]

  FILTERS = %w[buy_soon expiring].freeze
  TABS = %w[to_buy stocked all].freeze
  # To Buy's groups, one under another: out or past the buy-by date, buy within 7 days, expiring
  TO_BUY = { now: %i[out buy_now], soon: %i[buy_soon], expiring: %i[expiring] }.freeze

  # Three tabs, like Bills: To Buy (what to buy now, opens first), Stocked (enough for now, by the
  # month each moves to To Buy) and All (every item, with filters and search). A filter, category,
  # search or the archived list is always All
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
    all_only = @filter || @kind || @query.present? || params[:archived].present?
    @tab = all_only ? "all" : (params[:tab].presence_in(TABS) || "to_buy")
    @kinds_in_use = all.map { it.first.kind }.uniq
    @archived_count = Current.household.supplies.where.not(archived_at: nil).count
    @items = all.select { |supply, forecast| shown?(supply, forecast) }.sort_by { |supply, forecast| urgency(supply, forecast) }
    to_buy_and_stocked(all)
  end

  def show
    authorize @supply
    @forecast = @supply.forecast
    @history = @supply.history
    @price_history = @supply.price_history
    @stores = stores(@supply)
  end

  def new
    authorize Supply
    @supply = Current.household.supplies.new(prefill_params)
    @scan = scan_params
    @purchase = SupplyPurchase.new(purchased_on: Current.household.today)
  end

  # Already bought (the "I already bought these" section filled in): the purchase, then what's left
  # now (Supplies::PurchaseDetails); otherwise just the count
  def create
    authorize Supply
    @supply = Current.household.supplies.new(supply_params.merge(created_by: Current.user, level_at: Time.current))
    @scan = scan_params
    attributes = purchase_params
    bought = params[:log_purchase] == "1" || Supplies::PurchaseDetails.given?(attributes)
    attributes[:quantity] = @supply.level if attributes[:quantity].blank?
    attributes[:purchased_on] = Current.household.today if attributes[:purchased_on].blank?
    @purchase = SupplyPurchase.new(attributes)

    saved = Supply.transaction do
      raise ActiveRecord::Rollback unless @supply.save
      @supply.barcodes.create!(household: Current.household, code: @scan[:barcode]) if @scan[:barcode].present? && !Current.household.supply_barcodes.exists?(code: @scan[:barcode])
      if bought
        @purchase = Supplies::PurchaseDetails.for_new(@supply, attributes, level: @supply.level, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
        purchase_failed! unless @purchase.persisted?
      else
        Supplies::RecordCount.call(@supply, @supply.level, user: Current.user)
      end
      true
    end

    if saved
      redirect_to household_supply_path(Current.household, @supply), notice: t(".created", item: @supply.name)
    else
      @open_purchase = bought
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @supply
    @purchase = @supply.latest_purchase || SupplyPurchase.new(purchased_on: Current.household.today)
  end

  # The item's settings, and its latest purchase (price, store, date…), or the first one if none yet
  def update
    authorize @supply
    attributes = purchase_params
    @purchase = @supply.latest_purchase || SupplyPurchase.new(attributes)
    saved = Supply.transaction do
      raise ActiveRecord::Rollback unless @supply.update(supply_params.except(:level))
      if @supply.latest_purchase || Supplies::PurchaseDetails.given?(attributes)
        @purchase = Supplies::PurchaseDetails.for_edit(@supply, attributes, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
        purchase_failed! unless @purchase.persisted? && @purchase.errors.empty?
      end
      Supplies::StockChanged.call(@supply)
      true
    end

    if saved
      redirect_to household_supply_path(Current.household, @supply), notice: t(".saved")
    else
      @open_purchase = true
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
    @supply = Current.household.supplies.includes(:purchases, :counts, :prices).find(params[:id])
  end

  def supply_params = params.expect(supply: %i[name kind unit level guess_days_per_unit lead_days alert_when_left])

  def purchase_params
    params.fetch(:purchase, {}).permit(*Supplies::PurchaseDetails::FIELDS).to_h.symbolize_keys
  end

  # The purchase's errors show at the top of the form, and nothing is saved
  def purchase_failed!
    @purchase.errors.full_messages.each { @supply.errors.add(:base, it) }
    raise ActiveRecord::Rollback
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

  def urgency(supply, forecast)
    [ SuppliesHelper::STATUS_ORDER.index(forecast.status), forecast.buy_by || forecast.run_out_on || Date.new(9999), supply.name ]
  end

  # To Buy's three groups, Stocked's months (by the day each item moves to To Buy) and Not enough
  # data yet, and Next up: the stocked item that moves to To Buy first
  def to_buy_and_stocked(all)
    sorted = all.sort_by { |supply, forecast| urgency(supply, forecast) }
    @to_buy = TO_BUY.transform_values { |statuses| sorted.select { statuses.include?(it.last.status) } }
    ok = sorted.select { it.last.status == :ok }.sort_by { |supply, forecast| [ forecast.to_buy_on || Date.new(9999), supply.name ] }
    @stocked = ok.group_by { it.last.to_buy_on&.beginning_of_month }
    @no_data = sorted.select { it.last.status == :not_enough_data }
    @next_up = ok.find { it.last.to_buy_on }
    @counts = { to_buy: @to_buy.values.sum(&:size), stocked: ok.size + @no_data.size, all: all.size }
  end

  # Buy soon, Expiring, an estimated monthly spend (usage × the last price per unit) and the count
  def summary(all)
    monthly = all.sum do |supply, forecast|
      last = supply.latest_purchase
      forecast.enough_data? && last ? forecast.rate * 30 * last.unit_price : 0
    end
    { buy_soon: all.count { it.last.needs_buying? }, expiring: all.count { it.last.expiring? }, monthly:, total: all.size }
  end

  # Where to buy: each store's cheapest price per unit (purchases and old prices) and how often it
  # was used, cheapest first
  def stores(supply)
    supply.priced.group_by { it.store.presence || "—" }.map do |store, purchases|
      best = purchases.min_by(&:unit_price)
      { store:, best:, times: purchases.size }
    end.sort_by { it[:best].unit_price }
  end
end
