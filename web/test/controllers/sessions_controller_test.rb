require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_session_path
    assert_response :success
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "signs in a verified user" do
    post session_path, params: { email_address: "alex@example.com", password: "password123" }
    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "wrong password gets the generic error" do
    post session_path, params: { email_address: "alex@example.com", password: "wrong" }
    assert_redirected_to new_session_path
    assert_equal I18n.t("sessions.create.invalid"), flash[:alert]
    assert_nil cookies[:session_id]
  end

  test "an unconfirmed account can't sign in" do
    post session_path, params: { email_address: "pending@example.com", password: "password123" }
    assert_redirected_to new_session_path
    assert_equal I18n.t("sessions.create.invalid"), flash[:alert]
  end

  test "sign out ends the session" do
    sign_in_as users(:alex)
    delete session_path
    assert_redirected_to root_path
    assert_empty cookies[:session_id]
  end

  test "an active session slides forward at most once a day" do
    session_record = users(:alex).sessions.create!
    session_record.update_columns(last_seen_at: 2.days.ago, expires_at: 300.days.from_now)
    sign_in_with_cookie(session_record)

    get root_path
    assert_in_delta 1.year.from_now, session_record.reload.expires_at, 1.minute
  end

  test "an expired session is rejected" do
    session_record = users(:alex).sessions.create!
    session_record.update_columns(expires_at: 1.minute.ago)
    sign_in_with_cookie(session_record)

    get root_path
    assert_select "a[href=?]", new_session_path
  end

  private
    def sign_in_with_cookie(session_record)
      cookie_jar = ActionDispatch::TestRequest.create.cookie_jar
      cookie_jar.signed[:session_id] = session_record.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
end
