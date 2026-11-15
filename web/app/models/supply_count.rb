# A count of what's left: a −1 tap or "I have N left". Each one is an observation the forecast
# learns from; Undo deletes it.
class SupplyCount < ApplicationRecord
  belongs_to :supply
  belongs_to :created_by, class_name: "User", optional: true

  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }

  before_validation { self.counted_at ||= Time.current }

  def at = counted_at
end
