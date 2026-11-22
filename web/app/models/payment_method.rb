class PaymentMethod < ApplicationRecord
  belongs_to :household
  has_many :records, dependent: :restrict_with_error

  enum :kind, { card: "card", bank: "bank", e_wallet: "e_wallet", cash: "cash", other: "other" }, validate: true

  validates :name, presence: true, length: { maximum: 40 }
  validates :last4, format: { with: /\A\d{4}\z/ }, allow_blank: true
  # Only the last 4 digits are ever kept: a name holding a full card number (13+ digits, spaces or dashes
  # between them) is refused
  CARD_NUMBER = /\d(?:[ -]?\d){12,}/
  validates :name, format: { without: CARD_NUMBER, message: :card_number }
  # Card and Bank have last digits; for the others an empty Last 4 Digits is kept empty
  KINDS_WITH_LAST4 = %w[card bank].freeze

  # "玉山 ubear ··1234", as the menus and lists show it
  def label = last4.present? ? "#{name} ··#{last4}" : name

  scope :active, -> { where(archived_at: nil) }
end
