module Accounts
  # The owner promotes a member to owner and becomes co-owner (PRD §15). The household row lock
  # serializes concurrent transfers, and the old owner is demoted before the new one is promoted,
  # so the one-owner index never sees two owners and the household never has none.
  class OwnershipTransfer
    class NotAllowed < StandardError; end

    def self.call(household:, from:, to_membership:)
      household.with_lock do
        current = household.memberships.lock.find_by(role: "owner")
        raise NotAllowed unless current&.user_id == from.id && to_membership.household_id == household.id && to_membership.user_id != from.id

        current.update!(role: "co_owner")
        to_membership.reload.update!(role: "owner")
        SecurityEvent.record!("ownership_transferred", actor: from, user: to_membership.user, household:)
      end
    end
  end
end
