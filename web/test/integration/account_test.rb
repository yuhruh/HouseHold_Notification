require "test_helper"

class AccountTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:alex) }

  test "profile, locale and time zone update" do
    patch account_path, params: { user: { display_name: "Alex H", locale: "en", time_zone: "Europe/London", reminder_hour: 9 } }
    assert_redirected_to account_path
    user = users(:alex).reload
    assert_equal [ "Alex H", "en", "Europe/London", 9 ], [ user.display_name, user.locale, user.time_zone, user.reminder_hour ]
  end

  test "invalid input re-renders with inline errors" do
    patch account_path, params: { user: { time_zone: "Mars/Base" } }
    assert_response :unprocessable_content
    assert_select "ul.bg-red-50 li"
  end

  test "email change needs the current password, notifies the old address and switches only after confirmation" do
    patch account_email_path, params: { email_address: "new@example.com", current_password: "wrong" }
    assert_nil users(:alex).reload.unconfirmed_email

    assert_enqueued_emails(2) do
      patch account_email_path, params: { email_address: "new@example.com", current_password: "password123" }
    end
    user = users(:alex).reload
    assert_equal "alex@example.com", user.email_address
    assert_equal "new@example.com", user.unconfirmed_email
    assert_enqueued_email_with AuthMailer, :email_change_notice, params: { user:, locale: "zh-TW", old_email: "alex@example.com" }

    get email_confirmation_path(user.generate_token_for(:email_confirmation))
    assert_equal "new@example.com", user.reload.email_address
  end

  test "a Google-only user's email change needs re-auth" do
    sign_out
    sign_in_as users(:google_only)
    patch account_email_path, params: { email_address: "new@example.com" }
    assert_redirected_to reauthentication_path
  end

  test "password change needs the current password and signs out other sessions" do
    other = users(:alex).sessions.create!
    patch account_password_path, params: { current_password: "wrong", password: "newpassword1", password_confirmation: "newpassword1" }
    assert Session.exists?(other.id)

    patch account_password_path, params: { current_password: "password123", password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to account_path
    assert_not Session.exists?(other.id)
    assert users(:alex).reload.authenticate_password("newpassword1")
  end

  test "sign out other sessions keeps this one" do
    other = users(:alex).sessions.create!
    delete account_sessions_path
    assert_not Session.exists?(other.id)
    get account_path
    assert_response :success
  end

  test "signed-in devices are folded until opened" do
    get account_path
    assert_select "details#sessions:not([open]) summary", /\(1\)/
  end

  test "Google can't be disconnected when it's the last sign-in method" do
    sign_out
    sign_in_as users(:google_only)
    reauthenticate!
    delete account_google_identity_path
    assert users(:google_only).reload.google_identity
  end

  test "Google can be disconnected after re-auth when a password exists" do
    users(:alex).identities.create!(provider: "google_oauth2", uid: "alex-g")
    delete account_google_identity_path
    assert_redirected_to reauthentication_path
    reauthenticate!
    delete account_google_identity_path
    assert_nil users(:alex).reload.google_identity
  end
end
