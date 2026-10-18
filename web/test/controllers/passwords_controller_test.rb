require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "reset mail goes only to a verified address, with the same answer either way" do
    assert_enqueued_email_with PasswordsMailer, :reset, params: { user: users(:alex), locale: "zh-TW" } do
      post passwords_path, params: { email_address: "alex@example.com" }
    end
    assert_redirected_to new_session_path

    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: "pending@example.com" }
    end
    assert_redirected_to new_session_path
    assert_equal I18n.t("passwords.create.sent"), flash[:notice]
  end

  test "a Google-only user can set a first password through the reset link" do
    user = users(:google_only)
    put password_path(user.password_reset_token), params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to new_session_path

    post session_path, params: { email_address: "sam@example.com", password: "newpassword1" }
    assert_redirected_to root_path
  end

  test "an invalid token is rejected" do
    get edit_password_path("bogus")
    assert_redirected_to new_password_path
  end

  test "a too-short password is rejected" do
    token = users(:alex).password_reset_token
    put password_path(token), params: { password: "short", password_confirmation: "short" }
    assert_redirected_to edit_password_path(token)
  end
end
