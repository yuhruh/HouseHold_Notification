# A member's personal snooze on one record, on all channels (PRD §6): 3 days … at most 60 days
class ReminderSnooze < ApplicationRecord
  MAX_DAYS = 60

  belongs_to :record
  belongs_to :user

  validates :until_on, presence: true
end
