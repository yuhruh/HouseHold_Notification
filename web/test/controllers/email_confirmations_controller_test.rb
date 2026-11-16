require "test_helper"

class EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  def sign_up(email, password: "password123")
    post registration_path, params: { tz: "Asia/Taipei", user: { display_name: "New", unconfirmed_email: email, password:, password_confirmation: password } }
    User.where(unconfirmed_email: email).order(:id).last
  end

  test "in the browser that signed up, the link confirms the address and signs the user in" do
    user = sign_up("fresh@example.com")
    get email_confirmation_path(user.generate_token_for(:email_confirmation))
    assert_redirected_to root_path
    assert_equal "fresh@example.com", user.reload.email_address
    assert cookies[:session_id]
  end

  test "in any other browser the link asks for the sign-up password before it confirms anything" do
    user = users(:pending)
    token = user.generate_token_for(:email_confirmation)
    get email_confirmation_path(token)
    assert_response :success
    assert_select "form[action=?] input[type=password]", email_confirmation_path(token)
    assert_nil user.reload.email_address
    assert cookies[:session_id].blank?

    patch email_confirmation_path(token), params: { password: "not-the-password" }
    assert_redirected_to email_confirmation_path(token)
    assert_equal I18n.t("email_confirmations.update.wrong_password"), flash[:alert]
    assert_nil user.reload.email_address

    patch email_confirmation_path(token), params: { password: "password123" }
    assert_redirected_to root_path
    assert_equal "pending@example.com", user.reload.email_address
    assert cookies[:session_id]
  end

  test "someone who signs up with another person's address can't have that person confirm it for them" do
    squatter = sign_up("victim@example.com", password: "attacker-knows-this")
    token = squatter.generate_token_for(:email_confirmation)
    open_session do |victim|
      victim.get email_confirmation_path(token)
      victim.assert_response :success
      assert_nil squatter.reload.email_address, "opening the link in the victim's browser confirms nothing"
      assert victim.cookies[:session_id].blank?
    end
  end

  test "a changed address is confirmed only while signed in to that account" do
    user = users(:alex)
    user.update!(unconfirmed_email: "alex.new@example.com")
    token = user.generate_token_for(:email_confirmation)

    get email_confirmation_path(token)
    assert_redirected_to new_session_path
    assert_equal "alex@example.com", user.reload.email_address
    assert cookies[:session_id].blank?, "the link never signs anyone in to an existing account"

    post session_path, params: { email_address: "alex@example.com", password: "password123" }
    assert_redirected_to email_confirmation_url(token), "back to the link after signing in"
    follow_redirect!
    assert_redirected_to account_path
    assert_equal "alex.new@example.com", user.reload.email_address
  end

  test "a changed address isn't confirmed from another account" do
    user = users(:alex)
    user.update!(unconfirmed_email: "alex.new@example.com")
    sign_in_as users(:newbie)
    get email_confirmation_path(user.generate_token_for(:email_confirmation))
    assert_redirected_to root_path
    assert_equal I18n.t("email_confirmations.show.other_account"), flash[:alert]
    assert_equal "alex@example.com", user.reload.email_address
  end

  test "the sign-up cookie is set the same way whether or not the address had an account" do
    sign_up("brand-new@example.com")
    fresh = CGI.unescape(response.headers["Set-Cookie"].to_s[/signup=([^;]+)/, 1].to_s)
    sign_up("alex@example.com")
    existing = CGI.unescape(response.headers["Set-Cookie"].to_s[/signup=([^;]+)/, 1].to_s)
    assert fresh.present? && existing.present?
    assert_equal fresh.length, existing.length
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
