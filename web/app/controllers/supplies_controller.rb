# Supplies: what the household keeps in stock, how much is left, when it runs out and when to buy
# more (Supplies::Forecast). Everyone sees them; owners and co-owners add, edit and archive.
class SuppliesController < ApplicationController
  include HouseholdScoped
  before_action :set_supply, only: %i[show edit update archive destroy]

  TABS = %w[to_buy favorites all].freeze
  # The form's Category choice that makes a new one, named in new_category_name
  NEW_CATEGORY = "new".freeze
  # To Buy's groups, one under another: out or past the buy-by date, buy within 7 days, expiring
  TO_BUY = { now: %i[out buy_now], soon: %i[buy_soon], expiring: %i[expiring] }.freeze

  # Three tabs: To Buy (what to buy now), Favorites (the items anyone starred, or one person's with
  # `by`) and All (every item, with filters and search; Supplies opens on it, and each item with
  # enough for now says when it moves to To Buy). A filter, category, search or the archived list is
  # always All, and so is an old link to the Stocked tab, which All replaced. All's filters
  # are switches, any number at once: several categories show the items in any of them, and Expiring
  # keeps only the expiring ones among them
  def index
    authorize Supply
    supplies = Current.household.supplies.includes(:category, :purchases, :counts, :barcodes, :favorites)
    @supply_starrers = Supplies::Starrers.new(Current.household)
    supplies = params[:archived].present? ? supplies.where.not(archived_at: nil) : supplies.active
    @today = Current.household.today
    all = supplies.order(:name).map { [ it, it.forecast(today: @today) ] }
    @summary = summary(all)
    @expiring = params[:filter] == "expiring"
    @categories_in_use = all.map { it.first.category }.uniq.sort_by { [ it.position, it.id ] }
    chosen = Array.wrap(params[:category]).map { it.to_s.to_i }
    @chosen = @categories_in_use.select { chosen.include?(it.id) }
    @query = params[:q].to_s.strip
    @narrowed = @expiring || @chosen.any? || @query.present?
    all_only = @narrowed || params[:archived].present?
    # Supplies opens on All; an old "Buy soon" filter link opens To Buy, where those items are
    @tab = all_only ? "all" : (params[:tab].presence_in(TABS) || (params[:filter] == "buy_soon" ? "to_buy" : "all"))
    @archived_count = Current.household.supplies.where.not(archived_at: nil).count
    @items = all.select { |supply, forecast| shown?(supply, forecast) }.sort_by { |supply, forecast| urgency(supply, forecast) }
    to_buy_and_favorites(all)
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
    @supply.settle_category
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
      raise ActiveRecord::Rollback unless new_category_for(@supply) && @supply.save
      SupplyBarcode.remember(@supply, @scan[:barcode], product_name: @scan[:product_name].presence || @supply.name) if @scan[:barcode].present?
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

  # With two or more purchases to choose from (brands, or batches still in stock), Edit lists them and
  # corrects the one chosen (purchase_id); choosing another reloads only that part (the supply_purchase
  # frame)
  def edit
    authorize @supply
    @purchase = editing_purchase || SupplyPurchase.new(purchased_on: Current.household.today)
    @choices, @left = purchase_choices
  end

  # The item's settings, and the purchase being corrected (the latest, or the product's chosen on the
  # form: price, store, date…), or the first one if none yet
  def update
    authorize @supply
    attributes = purchase_params
    editing = editing_purchase
    @purchase = editing || SupplyPurchase.new(attributes)
    saved = Supply.transaction do
      raise ActiveRecord::Rollback unless new_category_for(@supply) && @supply.update(supply_params.except(:level))
      if editing || Supplies::PurchaseDetails.given?(attributes)
        @purchase = Supplies::PurchaseDetails.for_edit(@supply, attributes, purchase: editing, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
        purchase_failed! unless @purchase.persisted? && @purchase.errors.empty?
      end
      Supplies::StockChanged.call(@supply)
      true
    end

    if saved
      redirect_to household_supply_path(Current.household, @supply), notice: t(".saved")
    else
      @open_purchase = true
      @choices, @left = purchase_choices
      render :edit, status: :unprocessable_content
    end
  end

  # Archive hides the item and stops its alerts; its purchases stay in history and the Ledger
  def archive
    authorize @supply
    @supply.update!(archived_at: @supply.archived_at ? nil : Time.current)
    redirect_to household_supplies_path(Current.household), notice: t(@supply.archived_at ? ".archived" : ".restored", item: @supply.name)
  end

  # Delete removes the item for good, with its history, old prices, barcodes and stars. Expenses it
  # added to the Ledger stay. A receipt none of whose items are left can be added again
  def destroy
    authorize @supply
    Supply.transaction do
      imports = Current.household.receipt_imports.where(id: @supply.purchases.filter_map(&:receipt_import_id))
      @supply.destroy!
      imports.where.missing(:purchases).where(record_id: nil).destroy_all
    end
    redirect_to household_supplies_path(Current.household), notice: t(".deleted", item: @supply.name), status: :see_other
  end

  private

  def set_supply
    @supply = Current.household.supplies.includes(:category, :purchases, :counts, :prices, :barcodes, :favorites).find(params[:id])
  end

  # The purchase Edit corrects: the one chosen (purchase_id, one of this item's), else the latest
  def editing_purchase
    return @supply.latest_purchase if params[:purchase_id].blank?

    @supply.purchases.find { it.id == params[:purchase_id].to_i } || raise(ActiveRecord::RecordNotFound)
  end

  # The purchases Edit can correct: every one with some left (each batch on the item page) and the
  # latest of each product the item was bought as, newest first, with how many of each are left; nil
  # with only one, as then Edit corrects the latest
  def purchase_choices
    batches = @supply.brands.batches.select(&:purchase)
    latest = @supply.purchases.reject(&:new_record?).group_by { Supplies::Brands.key(it.product_name) }
                    .map { |_, purchases| purchases.max_by { [ it.purchased_on, it.created_at ] } }
    choices = (latest + batches.map(&:purchase)).uniq(&:id)
    return if choices.size < 2

    [ choices.sort_by { [ -it.purchased_on.jd, -it.created_at.to_f ] }, batches.to_h { [ it.purchase.id, it.left ] } ]
  end

  def supply_params
    params.expect(supply: %i[name supply_category_id unit level guess_days_per_unit lead_days alert_when_left]).tap do |attrs|
      attrs.delete(:supply_category_id) if adding_category?
    end
  end

  def adding_category? = params.dig(:supply, :supply_category_id) == NEW_CATEGORY

  # "＋ New category…" on the form: the category typed beside it is made with the item, or found by
  # its name if the ledger already has it. Without a usable name nothing is saved
  def new_category_for(supply)
    return true unless adding_category?

    authorize SupplyCategory, :create?
    @new_category = params[:new_category_name].to_s.squish
    if @new_category.empty?
      supply.errors.add(:base, t("supplies.form.new_category_blank"))
      return false
    end
    category = SupplyCategory.named(Current.household, @new_category)
    category.errors.full_messages.each { supply.errors.add(:base, it) }
    supply.category = category if category.persisted?
    category.persisted?
  end

  def purchase_params
    params.fetch(:purchase, {}).permit(*Supplies::PurchaseDetails::FIELDS).to_h.symbolize_keys
  end

  # The purchase's errors show at the top of the form, and nothing is saved
  def purchase_failed!
    @purchase.errors.full_messages.each { @supply.errors.add(:base, it) }
    raise ActiveRecord::Rollback
  end

  # From a scan: the product name, kind (a starting category's key) and barcode a lookup found (supplies/scans#barcode)
  def prefill_params
    params.permit(:name, :kind, :unit).to_h.symbolize_keys.tap do |attrs|
      attrs.delete(:kind) unless SupplyCategory::KEYS.include?(attrs[:kind])
      attrs.delete(:unit) unless Supply::UNITS.include?(attrs[:unit])
    end
  end

  def scan_params
    params.permit(:barcode, :source, :original_name, :brand, :product_name, :not_found, filled: []).to_h.symbolize_keys.tap do |scan|
      scan[:barcode] = scan[:barcode].to_s.gsub(/\D/, "").presence
      scan[:filled] = Array(scan[:filled]) & %w[name kind unit]
    end
  end

  def shown?(supply, forecast)
    return false if @expiring && !forecast.expiring?
    return false if @chosen.any? && @chosen.exclude?(supply.category)
    return false if @query.present? && searched(supply).none? { it.to_s.downcase.include?(@query.downcase) }
    true
  end

  # What the search looks in: the item's name, its stores, and the products (brands) it was bought as
  def searched(supply)
    [ supply.name ] + supply.purchases.flat_map { [ it.store, it.product_name ] } + supply.barcodes.map(&:product_name)
  end

  # The item running out first comes first: by status, then the earliest buy-by date. Items without a
  # date (not enough data yet) and ties go fewest left first, then A to Z
  def urgency(supply, forecast)
    [ SuppliesHelper::STATUS_ORDER.index(forecast.status), forecast.buy_by || forecast.run_out_on || Date.new(9999), forecast.on_hand_rounded, supply.name ]
  end

  # To Buy's three groups, Next up: the item with enough for now that moves to To Buy first, and
  # Favorites: the items with anyone's star (an item two people starred counts once), the ones to
  # restock soonest first; with `by`, one person's
  def to_buy_and_favorites(all)
    sorted = all.sort_by { |supply, forecast| urgency(supply, forecast) }
    @to_buy = TO_BUY.transform_values { |statuses| sorted.select { statuses.include?(it.last.status) } }
    @next_up = sorted.select { it.last.status == :ok && it.last.to_buy_on }.min_by { |supply, forecast| [ forecast.to_buy_on, supply.name ] }
    starred = sorted.select { @supply_starrers.starred?(it.first) }
    @by = (@supply_starrers.find(params[:by]) if @tab == "favorites")
    @favorites = @by ? starred.select { @supply_starrers.starred_by?(it.first, @by.user) } : starred
    @star_counts = @supply_starrers.people.index_with { |person| starred.count { @supply_starrers.starred_by?(it.first, person.user) } }
    @counts = { to_buy: @to_buy.values.sum(&:size), favorites: starred.size, all: all.size }
  end

  # Expiring, an estimated monthly spend (usage × the last price per unit) and the count
  def summary(all)
    monthly = all.sum do |supply, forecast|
      last = supply.latest_priced_purchase
      forecast.enough_data? && last ? forecast.rate * 30 * last.unit_price : 0
    end
    { expiring: all.count { it.last.expiring? }, monthly:, total: all.size }
  end

  # Where to buy: each store's cheapest price per unit, or per piece when every price says what was
  # in its pack (Supply#cheaper_first; purchases and old prices), and how often it was used, cheapest first
  def stores(supply)
    cheaper = supply.cheaper_first
    supply.priced.group_by { it.store.presence || "—" }.map do |store, purchases|
      best = purchases.min_by(&cheaper)
      { store:, best:, times: purchases.size }
    end.sort_by { cheaper.(it[:best]) }
  end
end
