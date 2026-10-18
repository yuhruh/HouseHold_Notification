require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  def invite(email = "newbie@example.com", expires_at: 7.days.from_now, role: "co_owner")
    Invitation.issue!(household: households(:home), invited_by: users(:alex), email:, role:, expires_at:)
  end

  test "stores only a digest of the token" do
    invitation = invite
    assert invitation.token.present?
    assert_not_equal invitation.token, invitation.token_digest
    assert_equal invitation, Invitation.find_by_token(invitation.token)
  end

  test "a new invitation for the same address revokes the open one" do
    first = invite
    second = invite
    assert first.reload.revoked_at
    assert_equal [ second ], Invitation.pending_for(users(:newbie)).to_a
  end

  test "acceptance needs the matching verified email" do
    invitation = invite
    assert_not invitation.acceptable_by?(users(:alex))
    assert_raises(ActiveRecord::RecordNotFound) { invitation.accept!(users(:alex)) }
    assert invitation.acceptable_by?(users(:newbie))
  end

  test "an unconfirmed address can't accept" do
    user = User.create!(unconfirmed_email: "newbie2@example.com", password: "password123")
    assert_not invite("newbie2@example.com").acceptable_by?(user)
  end

  test "7-day and 30-day invitations work on day 6 / 29 and not after" do
    seven = invite(expires_at: Invitation.expiry_from("7"))
    thirty = invite("other@example.com", expires_at: Invitation.expiry_from("30"))
    travel 6.days do
      assert seven.pending?
    end
    travel 8.days do
      assert_not seven.pending?
    end
    travel 29.days do
      assert thirty.pending?
    end
    travel 31.days do
      assert_not thirty.pending?
    end
  end

  test "a custom date is respected" do
    invitation = invite(expires_at: Invitation.expiry_from("custom", (Date.current + 10).iso8601))
    travel_to (Date.current + 10).in_time_zone.change(hour: 22) do
      assert invitation.pending?
    end
    travel_to (Date.current + 11).in_time_zone.change(hour: 1) do
      assert_not invitation.pending?
    end
  end

  test "a never-expiring invitation works a year later but is single use and revocable" do
    invitation = invite(expires_at: Invitation.expiry_from("never"))
    travel 1.year do
      invitation.accept!(users(:newbie))
      assert households(:home).users.include?(users(:newbie))
      assert_not invitation.reload.pending?
    end

    other = invite("other@example.com", expires_at: nil)
    other.revoke!
    assert_not other.pending?
  end

  test "masks the email for the wrong-account message" do
    assert_equal "m***@gmail.com", Invitation.new(email: "mum@gmail.com").masked_email
  end
end
