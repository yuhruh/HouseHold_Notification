require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "normalizes both email columns" do
    user = User.new(unconfirmed_email: " New@Example.COM ")
    assert_equal "new@example.com", user.unconfirmed_email
  end

  test "confirming moves the pending address into email_address" do
    user = users(:pending)
    assert user.confirm_email!
    assert_equal "pending@example.com", user.email_address
    assert_nil user.unconfirmed_email
    assert user.email_confirmed_at
  end

  test "confirming fails gracefully when someone verified the address first" do
    squatter = User.create!(unconfirmed_email: "alex@example.com", password: "password123")
    assert_not squatter.confirm_email!
    assert_nil squatter.email_address
    assert_equal "alex@example.com", squatter.unconfirmed_email
  end

  test "a confirmation token stops working when the pending address changes" do
    user = users(:pending)
    token = user.generate_token_for(:email_confirmation)
    user.update!(unconfirmed_email: "other@example.com")
    assert_nil User.find_by_token_for(:email_confirmation, token)
  end

  test "unknown time zones fall back to Asia/Taipei" do
    assert_equal "Europe/Paris", User.valid_time_zone("Europe/Paris")
    assert_equal "Asia/Taipei", User.valid_time_zone("Mars/Olympus")
    assert_equal "Asia/Taipei", User.valid_time_zone(nil)
  end

  test "an email address is exactly one address" do
    user = users(:alex)
    [ "a@x.com, b@y.com", "a@x.com b@y.com", "not-an-email", "a@x.com\nBcc: b@y.com", "#{"a" * 250}@x.com" ].each do |bad|
      assert_not user.update(unconfirmed_email: bad), bad
      assert_not User.new(unconfirmed_email: bad, password: "password123").valid?, bad
    end
    assert user.update(unconfirmed_email: "new.address+tag@example.co.uk")
  end

  test "a display name is one short line" do
    user = users(:alex)
    user.update!(display_name: "  Alex\r\nClick   here:\thttp://evil.example \u0000 ")
    assert_equal "Alex Click here: http://evil.example", user.display_name
    assert_not user.update(display_name: "x" * 61)
    assert user.update(display_name: "x" * 60)
  end

  test "an account from before these rules can still be saved" do
    user = users(:alex)
    user.update_columns(display_name: "x" * 200, unconfirmed_email: "a@x.com, b@y.com")
    assert user.reload.update(locale: "en")
  end
end
