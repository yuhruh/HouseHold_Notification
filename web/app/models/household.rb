class Household < ApplicationRecord
  CURRENCIES = %w[TWD USD].freeze

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :invitations, dependent: :destroy
  has_one :owner_membership, -> { where(role: "owner") }, class_name: "Membership"
  has_one :owner, through: :owner_membership, source: :user

  validates :name, presence: true, length: { maximum: 60 }
  validates :default_currency, inclusion: { in: CURRENCIES }
  validates :reminder_lead_days, numericality: { only_integer: true, in: 0..30 }

  # Recurring generation runs in the owner's zone (PRD §11)
  def time_zone = owner&.time_zone || User::DEFAULT_TIME_ZONE
end
