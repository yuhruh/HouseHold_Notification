class Household < ApplicationRecord
  CURRENCIES = %w[TWD USD].freeze
  # Currencies without cents: amounts are typed as whole numbers
  WHOLE_CURRENCIES = %w[TWD].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  # Deleted only by Households::Purge, in order
  has_many :categories
  has_many :category_aliases
  has_many :payment_methods
  has_many :payment_keywords
  has_many :records
  has_many :record_events
  has_many :import_batches
  has_many :import_keys
  has_many :import_previews
  has_many :recurring_templates
  has_many :reminder_deliveries
  has_one :owner_membership, -> { where(role: "owner") }, class_name: "Membership"
  has_one :owner, through: :owner_membership, source: :user

  validates :name, presence: true, length: { maximum: 60 }
  validates :default_currency, inclusion: { in: CURRENCIES }
  validates :reminder_lead_days, numericality: { only_integer: true, in: 0..30 }

  # Recurring generation runs in the owner's zone (PRD §11)
  def time_zone = owner&.time_zone || User::DEFAULT_TIME_ZONE
end
