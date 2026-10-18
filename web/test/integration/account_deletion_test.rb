require "test_helper"

class AccountDeletionTest < ActionDispatch::IntegrationTest
  test "/account/deletion is publicly reachable" do
    get account_deletion_path
    assert_response :success
  end

  test "an owner with members is blocked until ownership is transferred or the household is deleted" do
    sign_in_as users(:alex)
    reauthenticate!
    post account_deletion_path
    assert_response :unprocessable_content
    assert User.exists?(users(:alex).id)
  end

  test "a sole owner's deletion removes the household after typing its name" do
    user = users(:newbie)
    household = Households::Create.call(user:, params: { name: "Solo" })
    sign_in_as user
    reauthenticate!

    post account_deletion_path, params: { confirm: { household.id => "wrong" } }
    assert User.exists?(user.id)

    post account_deletion_path, params: { confirm: { household.id => "Solo" } }
    assert_redirected_to root_path
    assert_not User.exists?(user.id)
    assert_not Household.exists?(household.id)
  end

  test "a viewer's deletion removes their membership, sessions and identities and nullifies invitations they sent" do
    user = users(:google_only)
    households(:parents).memberships.where(user:).delete_all # not an owner anywhere
    accepted = Invitation.issue!(household: households(:home), invited_by: user, email: "a@example.com", role: "viewer", expires_at: nil)
    accepted.update!(accepted_at: Time.current)
    open_one = Invitation.issue!(household: households(:home), invited_by: user, email: "b@example.com", role: "viewer", expires_at: nil)
    sign_in_as user
    reauthenticate!

    assert_enqueued_email_with AccountMailer, :deleted, params: { email: "sam@example.com", locale: "zh-TW" } do
      post account_deletion_path
    end
    assert_not User.exists?(user.id)
    assert_empty Membership.where(user_id: user.id)
    assert_empty Session.where(user_id: user.id)
    assert_empty Identity.where(user_id: user.id)
    assert_nil accepted.reload.invited_by_id
    assert_not Invitation.exists?(open_one.id)
    assert SecurityEvent.exists?(kind: "account_deleted", user_id: user.id)
  end
end
