# Channel toggles per member and household (PRD §6, §13). Without a row the role decides:
# owners and co-owners default on, viewers off. bill_paid ("a utility bill was marked paid") also
# follows the role until the member changes it.
class NotificationPreference < ApplicationRecord
  belongs_to :user
  belongs_to :household

  validates :web_push, :email, inclusion: { in: [ true, false ] }

  def self.for(membership)
    pref = find_or_initialize_by(user_id: membership.user_id, household_id: membership.household_id) do |new_pref|
      new_pref.web_push = new_pref.email = membership.can_write?
    end
    pref.bill_paid = membership.can_write? if pref.bill_paid.nil?
    pref
  end
end
