class PaymentMethod < ApplicationRecord
  belongs_to :household
  has_many :records, dependent: :restrict_with_error

  enum :kind, { card: "card", bank: "bank", e_wallet: "e_wallet", cash: "cash", other: "other" }, validate: true

  validates :name, presence: true, length: { maximum: 40 }
  validates :last4, format: { with: /\A\d{4}\z/ }, allow_blank: true

  scope :active, -> { where(archived_at: nil) }
end
