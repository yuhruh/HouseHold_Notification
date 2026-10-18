require "test_helper"

class ReauthenticationTest < ActionDispatch::IntegrationTest
  test "password users confirm with their password and return to the page" do
    sign_in_as users(:alex)
    get account_deletion_path
    assert_redirected_to reauthentication_path

    post reauthentication_path, params: { password: "wrong" }
    assert_redirected_to reauthentication_path

    post reauthentication_path, params: { password: "password123" }
    assert_redirected_to account_deletion_path
    get account_deletion_path
    assert_response :success
  end

  test "Google-only users get an emailed code naming the action" do
    sign_in_as users(:google_only)
    get account_deletion_path
    assert_enqueued_emails(1) { post code_reauthentication_path }

    code = nil
    perform_enqueued_jobs { post code_reauthentication_path }
    code = ActionMailer::Base.deliveries.last.body.to_s[/\b\d{6}\b/]
    assert_match I18n.t("reauth_purposes.delete_account"), ActionMailer::Base.deliveries.last.body.to_s

    post reauthentication_path, params: { code: }
    assert_redirected_to account_deletion_path
  end

  test "a 4th code request within 10 minutes is rate-limited" do
    sign_in_as users(:google_only)
    3.times { post code_reauthentication_path }
    assert_no_enqueued_emails { post code_reauthentication_path }
    assert_equal I18n.t("auth.rate_limited"), flash[:alert]
  end

  test "re-auth older than 10 minutes asks again" do
    sign_in_as users(:alex)
    reauthenticate!
    get account_deletion_path
    assert_response :success
    travel 11.minutes do
      get account_deletion_path
      assert_redirected_to reauthentication_path
    end
  end
end
