require "test_helper"

class InvitationFlowTest < ActionDispatch::IntegrationTest
  def invite(email, role: "co_owner")
    Invitation.issue!(household: households(:home), invited_by: users(:alex), email:, role:, expires_at: 7.days.from_now)
  end

  test "invited email + password sign-up: confirm elsewhere, sign in, accept, exactly one membership" do
    invitation = invite("invitee@example.com")

    get invitation_link_path(invitation.token)
    assert_select "a[href=?]", new_registration_path(email: "invitee@example.com")

    post registration_path, params: { user: { unconfirmed_email: "invitee@example.com", password: "password123", password_confirmation: "password123" } }
    user = User.find_by!(unconfirmed_email: "invitee@example.com")
    assert user.confirm_email! # "another browser session"

    post session_path, params: { email_address: "invitee@example.com", password: "password123" }
    follow_redirect!
    assert_redirected_to invitations_path
    follow_redirect!
    assert_select "p", /我的家/

    post accept_invitation_path(invitation)
    assert_redirected_to household_path(households(:home))
    assert_equal [ households(:home) ], user.reload.households.to_a
    assert user.memberships.sole.co_owner?
  end

  test "the same via Google sign-up" do
    invitation = invite("gmailer@example.com")
    google_sign_in(uid: "gmailer-uid", email: "gmailer@example.com")
    follow_redirect!
    assert_redirected_to invitations_path

    post accept_invitation_path(invitation)
    assert_equal [ households(:home) ], User.find_by!(email_address: "gmailer@example.com").households.to_a
  end

  test "a different-email user on the link gets the mismatch message and can't accept" do
    invitation = invite("someone@gmail.com")
    sign_in_as users(:newbie)

    get invitation_link_path(invitation.token)
    assert_response :success
    assert_match "s***@gmail.com", response.body

    post accept_invitation_path(invitation)
    assert_response :not_found
    assert_not households(:home).users.include?(users(:newbie))
  end

  test "the link alone doesn't confirm an email or grant anything" do
    invitation = invite("pending@example.com")
    sign_in_as users(:pending)
    get invitation_link_path(invitation.token)
    assert_nil users(:pending).reload.email_address
  end

  test "declined, revoked or expired invitations are not shown" do
    declined = invite("newbie@example.com")
    declined.decline!(users(:newbie))
    revoked = Invitation.issue!(household: households(:parents), invited_by: users(:google_only), email: "newbie@example.com", role: "viewer", expires_at: nil)
    revoked.revoke!
    Invitation.issue!(household: households(:home), invited_by: users(:alex), email: "newbie@example.com", role: "viewer", expires_at: 1.minute.from_now)

    travel 2.minutes do
      sign_in_as users(:newbie)
      get invitations_path
      assert_select "p", text: I18n.t("invitations.index.none")
      get root_path
      assert_redirected_to onboarding_path
    end
  end

  test "an invalid or used link shows the not-available page" do
    get invitation_link_path("bogus")
    assert_response :not_found
  end

  test "declining keeps the user out of the household" do
    invitation = invite("newbie@example.com")
    sign_in_as users(:newbie)
    post decline_invitation_path(invitation)
    assert_redirected_to root_path
    assert_empty users(:newbie).households
  end
end
