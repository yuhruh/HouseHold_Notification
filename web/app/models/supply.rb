# A household consumable (toilet paper, shampoo, oat milk). `level`/`level_at` is the last known
# count: set by a purchase (left before + bought) or a count (−1, "I have N left"). How fast it's
# used, when it runs out and when to buy more come from Supplies::Forecast; alert_state makes each
# restock alert go once (Supplies::Alerts).
class Supply < ApplicationRecord
  KINDS = %w[toiletries cleaning kitchen food_drink health other].freeze
  UNITS = %w[piece roll bottle can pack box bag].freeze
  ALERT_STATES = %w[ok low out].freeze
  # Expiry alerts: perishables a week ahead, everything else a month
  EXPIRY_WINDOW_DAYS = { "food_drink" => 7, "health" => 7 }.freeze
  DEFAULT_EXPIRY_WINDOW_DAYS = 30

  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  has_many :purchases, class_name: "SupplyPurchase", dependent: :destroy
  has_many :prices, class_name: "SupplyPrice", dependent: :delete_all
  has_many :counts, class_name: "SupplyCount", dependent: :delete_all
  has_many :barcodes, class_name: "SupplyBarcode", dependent: :delete_all
  has_many :favorites, class_name: "SupplyFavorite", dependent: :delete_all

  normalizes :name, with: ->(name) { name.to_s.squish }

  validates :name, presence: true, length: { maximum: 60 }
  validates :kind, inclusion: { in: KINDS }
  validates :unit, inclusion: { in: UNITS }
  validates :alert_state, inclusion: { in: ALERT_STATES }
  validates :level, :alert_when_left, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }
  validates :lead_days, numericality: { only_integer: true, in: 0..30 }
  validates :guess_days_per_unit, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than: 10_000 }, allow_nil: true

  before_validation { self.level_at ||= Time.current }

  scope :active, -> { where(archived_at: nil) }

  def expiry_window_days = EXPIRY_WINDOW_DAYS.fetch(kind, DEFAULT_EXPIRY_WINDOW_DAYS)

  def forecast(today: household.today) = Supplies::Forecast.new(self, today:)

  def latest_purchase = purchases.max_by { [ it.purchased_on, it.created_at ] }

  # Purchases and counts, newest first (the item page's History)
  def history = (purchases.to_a + counts.to_a).sort_by { -it.at.to_f }

  # Purchases and old prices, newest first (the item page's Price history and Where to buy)
  def priced = purchases.to_a + prices.to_a
  def price_history = priced.sort_by { [ -it.purchased_on.jd, -(it.created_at || Time.current).to_f ] }
end
