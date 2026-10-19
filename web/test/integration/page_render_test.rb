require "test_helper"

# Renders every M1 page once, so a missing translation or broken template fails here
class PageRenderTest < ActionDispatch::IntegrationTest
  test "signed-out pages" do
    %w[/ /privacy /session/new /registration/new /passwords/new /email_confirmations/new /account/deletion].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "owner pages" do
    sign_in_as users(:alex)
    home = households(:home)
    get reauthentication_path
    assert_response :success
    reauthenticate!
    [ account_path, account_deletion_path, household_path(home), household_members_path(home), household_settings_path(home),
      new_household_ownership_transfer_path(home), new_household_deletion_path(home), invitations_path,
      household_records_path(home), new_household_record_path(home), household_payment_methods_path(home),
      new_household_payment_method_path(home), household_categories_path(home), new_household_category_path(home),
      new_household_import_path(home), household_recurring_templates_path(home), new_household_recurring_template_path(home),
      household_upcoming_path(home), household_dashboard_path(home), notifications_path, household_reminder_deliveries_path(home) ].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "Google-only re-auth page offers the emailed code" do
    sign_in_as users(:google_only)
    get reauthentication_path
    assert_select "input[name=code]"
  end

  test "onboarding and invitation link pages" do
    sign_in_as users(:newbie)
    get onboarding_path
    assert_response :success
    invitation = Invitation.issue!(household: households(:home), invited_by: users(:alex), email: "x@example.com", role: "viewer", expires_at: nil)
    get invitation_link_path(invitation.token)
    assert_response :success
  end

  test "every mail renders in both languages" do
    user = users(:alex)
    invitation = Invitation.issue!(household: households(:home), invited_by: user, email: "x@example.com", role: "viewer", expires_at: nil)
    pending = users(:pending)
    %w[zh-TW en].each do |locale|
      [ AuthMailer.with(user: pending, locale:).email_confirmation, AuthMailer.with(user:, locale:).already_registered,
        AuthMailer.with(user: pending, locale:, old_email: "old@example.com").email_change_notice,
        AuthMailer.with(user:, locale:, code: "123456", purpose: "delete_account").reauth_code,
        PasswordsMailer.with(user:, locale:).reset, InvitationMailer.with(invitation:, token: invitation.token, locale:).invite,
        AccountMailer.with(email: "gone@example.com", locale:).deleted ].each do |mail|
        assert mail.body.to_s.present?, mail.subject
      end
    end
  end
end
