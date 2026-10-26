require "test_helper"

class HouseholdsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "a new sign-up has zero households and lands on onboarding" do
    sign_in_as users(:newbie)
    get root_path
    assert_redirected_to onboarding_path
    assert_empty users(:newbie).households
  end

  test "onboarding creates a household owned by the user" do
    sign_in_as users(:newbie)
    post households_path, params: { household: { name: "Newbie home", default_currency: "TWD" } }
    household = users(:newbie).households.sole
    assert_redirected_to household_path(household)
    assert users(:newbie).memberships.sole.owner?
  end

  test "someone with a household can create another from My account" do
    sign_in_as users(:alex)
    get account_path
    assert_select "a[href=?]", onboarding_path
    get onboarding_path
    assert_response :success
    assert_select "h1", I18n.t("onboardings.show.new_title")
    assert_select "h2", text: I18n.t("onboardings.show.waiting_heading"), count: 0
    assert_difference -> { users(:alex).households.count } do
      post households_path, params: { household: { name: "Second home", default_currency: "TWD" } }
    end
    assert users(:alex).memberships.find_by(household: Household.find_by!(name: "Second home")).owner?
  end

  test "GET / goes to last_household_id, then the first membership" do
    user = users(:google_only)
    sign_in_as user
    user.update!(last_household: households(:parents))
    get root_path
    assert_redirected_to household_path(households(:parents))

    user.memberships.find_by(household: households(:parents)).destroy
    get root_path
    assert_redirected_to household_path(households(:home))
  end

  test "visiting a household records it as the last one" do
    sign_in_as users(:google_only)
    get household_path(households(:home))
    assert_equal households(:home), users(:google_only).reload.last_household
  end

  test "ledger home: one Bills card with what's to pay and the last bills paid, then the setup pages" do
    # Midday UTC: the same date in Taipei, where the page counts days
    travel_to Time.zone.local(2026, 10, 20, 12) do
      sign_in_as users(:alex)
      household = households(:home)
      Categories::Seed.call(household)
      water = household.categories.find_by!(name_zh: "水費")
      household.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "1月-2月"), settled: true, paid_on: Date.current - 3, amount_required: 412, amount_paid: 412)
      late = household.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "3月-4月"), due_on: Date.current - 5)
      get household_path(household)
      assert_select "a[href=?]", household_pending_path(household), /帳單/ do
        assert_select "span", "1 筆逾期"
        assert_select "span", "逾期 5 天"
        assert_select "span", /最近繳清/
      end
      assert_select "a[href=?]", household_recurring_templates_path(household)
      assert_select "main a[href=?]", household_dashboard_path(household), 0, "Expense Analysis only in the header and tab bar"

      late.update_columns(settled: true, paid_on: Date.current)
      get household_path(household)
      assert_select "a[href=?]", household_pending_path(household), /全部繳清了/
    end
  end

  test "a non-member gets 404 for every household URL" do
    sign_in_as users(:alex)
    get household_path(households(:parents))
    assert_response :not_found
    get household_members_path(households(:parents))
    assert_response :not_found
    post household_invitations_path(households(:parents)), params: { invitation: { email: "x@example.com", role: "viewer", expiry: "7" } }
    assert_response :not_found
  end

  test "two households in two tabs keep their own context" do
    sign_in_as users(:google_only)
    get household_members_path(households(:home))
    assert_select "h1", I18n.t("members.index.title")
    assert_select "header", /我的家/
    get household_members_path(households(:parents))
    assert_select "header", /Parents/
  end

  test "the household menu is named after the household; it lists every household with your role, ticks the current one and offers a new household" do
    sign_in_as users(:google_only)
    get household_path(households(:home))
    assert_select "header details summary", /我的家/
    assert_select "header details a[href=?]", household_path(households(:parents)), /Parents/
    assert_select "header details a[aria-current=true][href=?]", household_path(households(:home)), /我的家/
    assert_select "header details a[href=?]", onboarding_path
    assert_select "header details a[href=?]", household_settings_path(households(:home)), /帳本設定/
    assert_select "header details a[href=?]", household_members_path(households(:home)), /成員/

    sign_out
    sign_in_as users(:alex)
    get household_path(households(:home))
    assert_select "header details a[href=?]", household_path(households(:home)), 1, "one household, still in the menu"
    assert_select "header details a[href=?]", household_path(households(:parents)), 0
  end

  test "the Household Tracker logo goes to the features page, which works signed in and out" do
    sign_in_as users(:alex)
    get household_path(households(:home))
    assert_select "header a[href=?]", features_path, /Household Tracker/
    get features_path
    assert_select "h1", /功能介紹/
    assert_select "a[href=?]", guide_path

    sign_out
    get features_path, headers: { "Accept-Language" => "en" }
    assert_response :success
    assert_select "h1", /Features/
  end

  test "a viewer can't invite (Pundit, server-side)" do
    sign_in_as users(:google_only)
    post household_invitations_path(households(:home)), params: { invitation: { email: "x@example.com", role: "viewer", expiry: "7" } }
    assert_response :forbidden
  end

  test "the owner invites, resends and revokes" do
    sign_in_as users(:alex)
    assert_enqueued_emails(1) do
      post household_invitations_path(households(:home)), params: { invitation: { email: "Newbie@Example.com", role: "co_owner", expiry: "30" } }
    end
    invitation = households(:home).invitations.pending.sole
    assert_equal "newbie@example.com", invitation.email
    assert_in_delta 30.days.from_now, invitation.expires_at, 1.minute

    post resend_household_invitation_path(households(:home), invitation), params: { expiry: "never" }
    assert invitation.reload.revoked_at
    resent = households(:home).invitations.pending.sole
    assert_nil resent.expires_at

    post revoke_household_invitation_path(households(:home), resent)
    assert_empty households(:home).invitations.pending
  end
end
