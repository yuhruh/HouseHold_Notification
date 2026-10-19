# Channel toggles per member and household (PRD §6, §13). Without a row the role decides:
# owners and co-owners default on, viewers off.
class NotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :household

  validates :web_push, :email, inclusion: { in: [ true, false ] }

  def self.for(membership)
    find_or_initialize_by(user_id: membership.user_id, household_id: membership.household_id) do |pref|
      pref.web_push = pref.email = membership.can_write?
    end
  end
end
