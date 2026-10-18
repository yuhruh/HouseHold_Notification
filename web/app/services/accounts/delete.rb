module Accounts
  # Deletes a user (PRD §15). An owner whose household has other members must transfer or delete it
  # first; a household where they're the only member goes with them, once they've typed its name.
  class Delete
    Result = Data.define(:ok, :blocking, :unconfirmed)

    def self.call(user:, confirmations: {})
      owned = user.memberships.includes(household: :memberships).select(&:owner?).map(&:household)
      blocking = owned.select { |h| h.memberships.size > 1 }
      sole = owned - blocking
      unconfirmed = sole.reject { |h| confirmations[h.id.to_s].to_s.strip == h.name }
      return Result.new(false, blocking, unconfirmed) if blocking.any? || unconfirmed.any?

      User.transaction do
        sole.each { |household| Households::Purge.call(household, actor: user) }
        user.sent_invitations.open.delete_all
        SecurityEvent.record!("account_deleted", user:)
        user.destroy!
      end
      Result.new(true, [], [])
    end
  end
end
