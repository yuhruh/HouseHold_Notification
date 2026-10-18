require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def sign_up(email, password: "password123", tz: "Asia/Taipei")
    post registration_path, params: { tz:, user: { display_name: "New", unconfirmed_email: email, password:, password_confirmation: password } }
  end

  test "a new address gets a pending account and a confirmation email" do
    assert_enqueued_emails(1) { sign_up("new@example.com", tz: "Europe/Paris") }
    assert_response :success
    user = User.find_by!(unconfirmed_email: "new@example.com")
    assert_nil user.email_address
    assert_equal "Europe/Paris", user.time_zone
  end

  test "the response is identical for an existing address, whose owner gets the already-registered mail" do
    sign_up("someone-new@example.com")
    new_body = response.body

    assert_no_difference("User.count") do
      assert_enqueued_email_with AuthMailer, :already_registered, params: { user: users(:alex), locale: "zh-TW" } do
        sign_up("alex@example.com")
      end
    end
    assert_response :success
    assert_equal new_body.gsub(/name="authenticity_token" value="[^"]+"/, ""), response.body.gsub(/name="authenticity_token" value="[^"]+"/, "")
  end

  test "an unconfirmed sign-up doesn't block the real owner, who can confirm" do
    sign_up("shared@example.com")
    squatter = User.find_by!(unconfirmed_email: "shared@example.com")
    sign_up("shared@example.com")
    owner = User.where(unconfirmed_email: "shared@example.com").where.not(id: squatter.id).sole

    get email_confirmation_path(owner.generate_token_for(:email_confirmation))
    assert_equal "shared@example.com", owner.reload.email_address

    get email_confirmation_path(squatter.generate_token_for(:email_confirmation))
    assert_redirected_to new_session_path
    assert_equal I18n.t("email_confirmations.show.taken"), flash[:alert]
  end

  test "a short password is rejected the same way for new and existing addresses" do
    sign_up("brand-new@example.com", password: "short")
    assert_response :unprocessable_content
    sign_up("alex@example.com", password: "short")
    assert_response :unprocessable_content
  end

  test "an invalid time zone falls back to Asia/Taipei" do
    sign_up("tz@example.com", tz: "Not/AZone")
    assert_equal "Asia/Taipei", User.find_by!(unconfirmed_email: "tz@example.com").time_zone
  end
end
