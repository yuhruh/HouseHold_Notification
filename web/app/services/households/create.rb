module Households
  # A household and its owner membership, together (onboarding, PRD §12a)
  class Create
    def self.call(user:, params:)
      household = Household.new(params)
      Household.transaction do
        household.save!
        household.memberships.create!(user:, role: "owner")
        user.update!(last_household: household)
      end
      household
    rescue ActiveRecord::RecordInvalid
      household
    end
  end
end
