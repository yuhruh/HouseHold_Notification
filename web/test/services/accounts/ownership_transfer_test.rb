require "test_helper"

class Accounts::OwnershipTransferTest < ActiveSupport::TestCase
  test "leaves exactly one owner and makes the old owner a co-owner" do
    household = households(:home)
    Accounts::OwnershipTransfer.call(household:, from: users(:alex), to_membership: memberships(:sam_home))
    assert_equal [ users(:google_only) ], household.memberships.where(role: "owner").map(&:user)
    assert memberships(:alex_home).reload.co_owner?
  end

  test "only the current owner can transfer" do
    assert_raises(Accounts::OwnershipTransfer::NotAllowed) do
      Accounts::OwnershipTransfer.call(household: households(:home), from: users(:google_only), to_membership: memberships(:alex_home))
    end
  end

  # Sequential stand-in for the race: the second transfer sees the new owner under the row lock
  test "two concurrent transfers can't produce two owners or none" do
    household = households(:home)
    third = household.memberships.create!(user: users(:newbie), role: "viewer")

    results = [ memberships(:sam_home), third ].map do |target|
      Accounts::OwnershipTransfer.call(household: household.reload, from: users(:alex), to_membership: target)
      :ok
    rescue Accounts::OwnershipTransfer::NotAllowed
      :refused
    end

    assert_equal %i[ok refused], results
    assert_equal 1, household.memberships.where(role: "owner").count
  end
end
