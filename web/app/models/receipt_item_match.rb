# What a receipt line from a store meant last time: one of the household's supplies (and how many
# units one line is, e.g. 1 pack = 12 rolls), or nothing (supply_id nil = skip)
class ReceiptItemMatch < ApplicationRecord
  belongs_to :household
  belongs_to :supply, optional: true

  validates :receipt_text, presence: true
  validates :units_per_line, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than: 10_000 }
end
