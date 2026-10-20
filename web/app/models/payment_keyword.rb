# A payment keyword found in record notes ("ubear", "中信轉帳") and the payment method it stands for.
# No payment method means "skip". Matching ignores case, width and spaces.
class PaymentKeyword < ApplicationRecord
  belongs_to :household
  belongs_to :payment_method, optional: true

  validates :keyword, presence: true, length: { maximum: 40 }, uniqueness: { scope: :household_id }

  scope :ordered, -> { order(:position, :id) }

  def self.normalize(text) = text.to_s.unicode_normalize(:nfkc).downcase.gsub(/\s+/, "")

  def self.match?(keyword, note) = normalize(note).include?(normalize(keyword))
end
