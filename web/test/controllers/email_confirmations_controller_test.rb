require "test_helper"

class EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  test "the link confirms the address and signs the user in" do
    user = users(:pending)
    get email_confirmation_path(user.generate_token_for(:email_confirmation))
    assert_redirected_to root_path
    assert_equal "pending@example.com", user.reload.email_address
    assert cookies[:session_id]
  end

  test "an invalid link offers a resend" do
    get email_confirmation_path("bogus")
    assert_redirected_to new_email_confirmation_path
  end

  test "resend gives the same answer whether or not the address is pending" do
    assert_enqueued_email_with AuthMailer, :email_confirmation, params: { user: users(:pending), locale: "zh-TW" } do
      post email_confirmations_path, params: { email_address: "pending@example.com" }
    end
    assert_redirected_to new_session_path

    assert_no_enqueued_emails { post email_confirmations_path, params: { email_address: "nobody@example.com" } }
    assert_redirected_to new_session_path
  end
end
