# A household consumable (toilet paper, shampoo, oat milk). `level`/`level_at` is the last known
# count: set by a purchase (left before + bought) or a count (−1, "I have N left"). How fast it's
# used, when it runs out and when to buy more come from Supplies::Forecast; alert_state makes each
# restock alert go once (Supplies::Alerts).
class Supply < ApplicationRecord
  UNITS = %w[piece roll bottle can pack box bag].freeze
  # Counted in one of these, each purchase can say what was in each ("Each pack has 4 pieces", per
  # brand: Priced), for the price per piece. "Used 1 pack", the count and the forecast stay in packs
  PACKS = %w[pack box bag].freeze
  PACK_UNITS = %w[piece roll bottle can].freeze
  ALERT_STATES = %w[ok low out].freeze
  # Expiry alerts: a week ahead in a category that goes off quickly, everything else a month
  PERISHABLE_EXPIRY_WINDOW_DAYS = 7
  DEFAULT_EXPIRY_WINDOW_DAYS = 30

  belongs_to :household
  belongs_to :category, class_name: "SupplyCategory", foreign_key: :supply_category_id, inverse_of: :supplies
  belongs_to :created_by, class_name: "User", optional: true
  has_many :purchases, class_name: "SupplyPurchase", dependent: :destroy
  has_many :prices, class_name: "SupplyPrice", dependent: :delete_all
  has_many :counts, class_name: "SupplyCount", dependent: :delete_all
  has_many :barcodes, class_name: "SupplyBarcode", dependent: :delete_all
  has_many :favorites, class_name: "SupplyFavorite", dependent: :delete_all
  # What a store's receipt line meant; without the item the line is asked about again
  has_many :receipt_item_matches, dependent: :delete_all

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, length: { maximum: 60 }
  validates :unit, inclusion: { in: UNITS }
  validates :alert_state, inclusion: { in: ALERT_STATES }
  validates :level, :alert_when_left, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }
  validates :lead_days, numericality: { only_integer: true, in: 0..30 }
  validates :guess_days_per_unit, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than: 10_000 }, allow_nil: true

  validate { errors.add(:category, :invalid) if category && category.household_id != household_id }

  before_validation { self.level_at ||= Time.current }
  before_validation :settle_category

  scope :active, -> { where(archived_at: nil) }

  def in_packs? = unit.in?(PACKS)

  def expiry_window_days = category.perishable? ? PERISHABLE_EXPIRY_WINDOW_DAYS : DEFAULT_EXPIRY_WINDOW_DAYS

  # `kind` names one of the six starting categories by its key ("kitchen"), the way a barcode lookup
  # guesses it. It becomes the ledger's category with that key once the ledger is known, unless a
  # category was chosen as well; an item with neither goes in Other
  def kind=(key)
    @kind = key.to_s.presence
  end

  def kind = @kind || category&.key

  def settle_category
    return unless household

    self.category = SupplyCategory.for_key(household, @kind) if @kind && !supply_category_id_changed?
    @kind = nil
    self.category ||= SupplyCategory.fallback(household)
  end

  def forecast(today: household.today) = Supplies::Forecast.new(self, today:)

  # What is left of each brand (an item can be several brands; they share its count and forecast)
  def brands(forecast = self.forecast) = forecast.brands

  def latest_purchase = purchases.max_by { [ it.purchased_on, it.created_at ] }

  # Purchases and counts, newest first (the item page's History)
  def history = (purchases.to_a + counts.to_a).sort_by { -it.at.to_f }

  # Purchases and old prices, newest first (the item page's Price history and Where to buy)
  def priced = purchases.to_a + prices.to_a
  def price_history = priced.sort_by { [ -it.purchased_on.jd, -(it.created_at || Time.current).to_f ] }

  # Each brand's pack size, from its newest purchase or old price that has one: { "Brand A" => [4,
  # "piece"] } ("" for no brand). Fills in the size when that brand is bought again
  def pack_sizes
    price_history.select(&:pack_size).reverse.to_h { [ Supplies::Brands.key(it.product_name), [ it.pack_size, it.pack_unit ] ] }
  end

  # The size a brand came in last time, [4, "piece"], or nil; the item's own name is no brand
  def pack_size_for(product_name) = pack_sizes[Supplies::Brands.key(product_name == name ? nil : product_name&.squish)]

  # What "cheapest" compares: the price per piece when every purchase and old price says what's in
  # its pack (and the same kind: pieces, rolls…), so a pack of 20 at NT$12 a piece beats a pack of 4
  # at NT$15; otherwise the price per pack, box or bag, as for any other unit
  def cheaper_first
    all = priced
    by_piece = all.any? && all.all?(&:packed?) && all.map(&:pack_unit).uniq.one?
    by_piece ? :piece_price.to_proc : :unit_price.to_proc
  end
end
