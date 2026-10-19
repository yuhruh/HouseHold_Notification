# The in-app inbox (PRD → Data model)
class Notification < ApplicationRecord
  belongs_to :household
  belongs_to :user
  belongs_to :reminder_delivery, optional: true

  scope :unread, -> { where(read_at: nil) }

  validates :kind, :title, presence: true
end
