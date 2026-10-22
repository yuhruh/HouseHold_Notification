require "test_helper"

class HouseholdSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    sign_in_as users(:alex)
  end

  test "a new household has lead days 3; the owner sets 5 and it's saved with an audit entry" do
    assert_equal 3, Household.new.reminder_lead_days
    patch household_settings_path(@home), params: { household: { name: "我的家 2", default_currency: "USD", reminder_lead_days: 5 } }
    assert_redirected_to household_settings_path(@home)
    assert_equal [ "我的家 2", "USD", 5 ], @home.reload.values_at(:name, :default_currency, :reminder_lead_days)
    assert SecurityEvent.exists?(kind: "household_updated", household_id: @home.id)
  end

  test "the activity log says who did what to whom" do
    I18n.with_locale(:en) do
      patch household_membership_path(@home, memberships(:sam_home)), params: { membership: { role: "co_owner" } }
      patch household_settings_path(@home), params: { household: { reminder_lead_days: 5 } }
      Invitation.issue!(household: @home, invited_by: users(:alex), email: users(:newbie).email_address, role: "viewer", expires_at: nil)
        .accept!(users(:newbie))
      users(:alex).update!(locale: "en")
      get household_settings_path(@home)
      assert_select "li", text: /Alex Changed Sam's Role To Co-owner/
      assert_select "li", text: /Alex Changed Household Settings: #{Household.human_attribute_name(:reminder_lead_days)}/
      assert_select "li", text: /Joined As Viewer/
    end
  end

  test "lead days outside 0–30 show an inline error" do
    patch household_settings_path(@home), params: { household: { reminder_lead_days: 31 } }
    assert_response :unprocessable_content
    assert_select "ul.bg-red-50 li"
  end

  test "owner changes a role and removes a member, each audited" do
    patch household_membership_path(@home, memberships(:sam_home)), params: { membership: { role: "co_owner" } }
    assert memberships(:sam_home).reload.co_owner?
    delete household_membership_path(@home, memberships(:sam_home))
    assert_not Membership.exists?(memberships(:sam_home).id)
    assert_equal %w[member_removed role_changed], SecurityEvent.where(household_id: @home.id).order(:created_at).pluck(:kind).reverse
  end

  test "the owner's own role can't be changed here" do
    patch household_membership_path(@home, memberships(:alex_home)), params: { membership: { role: "viewer" } }
    assert_response :unprocessable_content
  end

  test "transfer needs re-auth" do
    get new_household_ownership_transfer_path(@home)
    assert_redirected_to reauthentication_path
    reauthenticate!
    post household_ownership_transfer_path(@home), params: { membership_id: memberships(:sam_home).id }
    assert memberships(:sam_home).reload.owner?
  end

  test "household deletion needs re-auth and the typed name" do
    reauthenticate!
    post household_deletion_path(@home), params: { confirm_name: "nope" }
    assert Household.exists?(@home.id)
    post household_deletion_path(@home), params: { confirm_name: "我的家" }
    assert_redirected_to root_path
    assert_not Household.exists?(@home.id)
  end
end
