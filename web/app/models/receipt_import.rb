# A Taiwan e-invoice (發票) imported from its QR codes. The invoice number is unique per household,
# so the same receipt can't be added twice.
class ReceiptImport < ApplicationRecord
  belongs_to :household
  belongs_to :record, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :purchases, class_name: "SupplyPurchase", dependent: :nullify

  validates :invoice_no, presence: true, uniqueness: { scope: :household_id }
  validates :issued_on, :total, presence: true
end
