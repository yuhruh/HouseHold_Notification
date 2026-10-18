require "test_helper"

# PRD §12 permission matrix for what exists so far
class RolesTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    @co = @home.memberships.create!(user: users(:newbie), role: "co_owner")
  end

  def as(user) = sign_in_as(user)

  test "co-owner and viewer can't edit settings, including lead days" do
    [ users(:newbie), users(:google_only) ].each do |user|
      as user
      patch household_settings_path(@home), params: { household: { reminder_lead_days: 5 } }
      assert_response :forbidden
      sign_out
    end
    assert_equal 3, @home.reload.reminder_lead_days
  end

  test "co-owner can't invite, change roles, remove members, transfer or delete" do
    as users(:newbie)
    post household_invitations_path(@home), params: { invitation: { email: "x@example.com", role: "viewer", expiry: "7" } }
    assert_response :forbidden
    patch household_membership_path(@home, memberships(:sam_home)), params: { membership: { role: "co_owner" } }
    assert_response :forbidden
    delete household_membership_path(@home, memberships(:sam_home))
    assert_response :forbidden
    get new_household_ownership_transfer_path(@home)
    assert_response :forbidden
    get new_household_deletion_path(@home)
    assert_response :forbidden
  end

  test "everyone can see settings and members" do
    [ users(:alex), users(:newbie), users(:google_only) ].each do |user|
      as user
      get household_settings_path(@home)
      assert_response :success
      get household_members_path(@home)
      assert_response :success
      sign_out
    end
  end

  test "owner can't leave; others can" do
    as users(:alex)
    post leave_household_memberships_path(@home)
    assert @home.memberships.exists?(user: users(:alex))
    sign_out

    as users(:google_only)
    post leave_household_memberships_path(@home)
    assert_not @home.memberships.exists?(user: users(:google_only))
    assert SecurityEvent.exists?(kind: "member_left", household_id: @home.id)
  end
end
