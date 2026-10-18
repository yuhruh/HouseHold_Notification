require "test_helper"

class ReauthCodeTest < ActiveSupport::TestCase
  setup { @user = users(:google_only) }

  test "a correct code works once" do
    _, code = ReauthCode.issue!(@user, "delete_account")
    assert ReauthCode.verify(@user, code)
    assert_not ReauthCode.verify(@user, code)
  end

  test "an expired code is rejected" do
    _, code = ReauthCode.issue!(@user, "delete_account")
    travel 11.minutes do
      assert_not ReauthCode.verify(@user, code)
    end
  end

  test "a code for another user is rejected" do
    _, code = ReauthCode.issue!(users(:alex), "delete_account")
    assert_not ReauthCode.verify(@user, code)
  end

  test "after 5 wrong attempts even the right code is rejected" do
    _, code = ReauthCode.issue!(@user, "delete_account")
    wrong = code == "000000" ? "111111" : "000000"
    5.times { assert_not ReauthCode.verify(@user, wrong) }
    assert_not ReauthCode.verify(@user, code)
  end

  test "a new code replaces the old one and only a digest is stored" do
    first_record, first = ReauthCode.issue!(@user, "delete_account")
    _, second = ReauthCode.issue!(@user, "delete_account")
    assert_not_equal first, first_record.code_digest
    assert_not ReauthCode.verify(@user, first) unless first == second
    assert ReauthCode.verify(@user, second)
  end
end
