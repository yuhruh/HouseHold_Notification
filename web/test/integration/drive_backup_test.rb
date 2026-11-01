require "test_helper"

class DriveBackupTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  KEYS = { "GOOGLE_DRIVE_CLIENT_ID" => "client-id", "GOOGLE_DRIVE_CLIENT_SECRET" => "client-secret" }.freeze

  setup do
    @home = households(:home)
    @saved = ENV.to_h.slice(*KEYS.keys)
    KEYS.each { |key, value| ENV[key] = value }
  end

  teardown { KEYS.each_key { |key| ENV[key] = @saved[key] } }

  def connect_flow(code: "the-code")
    post household_drive_backup_path(@home)
    assert_redirected_to(/accounts\.google\.com/)
    url = URI(response.location)
    params = Rack::Utils.parse_query(url.query)
    assert_equal DriveBackups::Oauth::SCOPE, params["scope"]
    assert_equal "offline", params["access_type"]
    params["state"]
  end

  def with_google(&block)
    with_stub(DriveBackups::Oauth, :exchange, "refresh-token") do
      with_stub(DriveBackups::Client, :new, FakeDrive.new, &block)
    end
  end

  test "stays hidden until the Google client is set" do
    sign_in_as users(:alex)
    KEYS.each_key { |key| ENV[key] = nil }
    get household_settings_path(@home)
    assert_select "#drive-backup", 0
    post household_drive_backup_path(@home)
    assert_response :not_found
  end

  test "the owner connects after re-authenticating; the token is stored encrypted and a first backup starts" do
    sign_in_as users(:alex)
    get household_settings_path(@home)
    assert_select "#drive-backup button", /連結 Google 雲端硬碟/
    post household_drive_backup_path(@home)
    assert_redirected_to reauthentication_path

    reauthenticate!(Session.last)
    state = connect_flow
    assert_enqueued_jobs(1, only: DriveBackupJob) do
      with_google { get google_drive_callback_path, params: { state:, code: "the-code" } }
    end
    assert_redirected_to household_settings_path(@home)
    backup = @home.reload.drive_backup
    assert_equal "alex@example.com", backup.google_email
    assert_equal "refresh-token", backup.refresh_token
    assert_not_includes DriveBackup.connection.select_value("SELECT refresh_token FROM drive_backups WHERE id = #{backup.id}"), "refresh-token"
    assert SecurityEvent.exists?(kind: "drive_backup_connected", household_id: @home.id)
  end

  test "a callback with the wrong state connects nothing" do
    sign_in_as users(:alex)
    reauthenticate!(Session.last)
    connect_flow
    with_google { get google_drive_callback_path, params: { state: "forged", code: "x" } }
    assert_nil @home.reload.drive_backup
  end

  test "declining at Google connects nothing" do
    sign_in_as users(:alex)
    reauthenticate!(Session.last)
    state = connect_flow
    get google_drive_callback_path, params: { state:, error: "access_denied" }
    assert_redirected_to household_settings_path(@home)
    assert_nil @home.reload.drive_backup
  end

  test "a browser sending a null origin can connect with a valid token, but not without one" do
    sign_in_as users(:alex)
    reauthenticate!(Session.last)
    ActionController::Base.allow_forgery_protection = true
    get household_settings_path(@home)
    token = css_select("#drive-backup form input[name=authenticity_token]").first["value"]
    post household_drive_backup_path(@home), params: { authenticity_token: token }, headers: { "Origin" => "null" }
    assert_redirected_to(/accounts\.google\.com/)
    post household_drive_backup_path(@home), params: { authenticity_token: "wrong" }, headers: { "Origin" => "null" }
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "members who aren't the owner can't see or use it" do
    sign_in_as users(:google_only) # a viewer
    get household_settings_path(@home)
    assert_select "#drive-backup", 0
    post household_drive_backup_path(@home)
    assert_not_includes response.location.to_s, "accounts.google.com"
    assert_nil @home.reload.drive_backup
  end

  test "Back Up Now, the states, and disconnecting" do
    backup = DriveBackup.create!(household: @home, connected_by: users(:alex), google_email: "alex@example.com", refresh_token: "token",
      folder_id: "abc", last_backup_at: Time.current, bills_count: 3, photos_count: 2)
    sign_in_as users(:alex)
    get household_settings_path(@home)
    assert_select "#drive-backup", /alex@example.com/
    assert_select "#drive-backup a[href=?]", "https://drive.google.com/drive/folders/abc"
    assert_enqueued_jobs(1, only: DriveBackupJob) { post run_household_drive_backup_path(@home) }

    backup.update!(running_since: Time.current)
    assert_no_enqueued_jobs(only: DriveBackupJob) { post run_household_drive_backup_path(@home) }

    backup.update!(running_since: nil, problem: "reconnect")
    get household_settings_path(@home)
    assert_select "#drive-backup button", /重新連結/
    assert_select "#drive-backup", /Google 存取權已被移除/

    with_stub(DriveBackups::Oauth, :revoke, nil) { delete household_drive_backup_path(@home) }
    assert_nil @home.reload.drive_backup
    assert SecurityEvent.exists?(kind: "drive_backup_disconnected", household_id: @home.id)
  end

  test "reconnecting with another Google account starts over; the same account carries on" do
    backup = DriveBackup.create!(household: @home, connected_by: users(:alex), google_email: "old@example.com", refresh_token: "old", folder_id: "abc")
    backup.files.create!(blob_id: 1, drive_file_id: "x")
    DriveBackups::Connect.call(household: @home, user: users(:alex), refresh_token: "new", client: FakeDrive.new)
    assert_nil backup.reload.folder_id
    assert_equal 0, backup.files.count

    backup.update!(folder_id: "def", problem: "reconnect")
    DriveBackups::Connect.call(household: @home, user: users(:alex), refresh_token: "newer", client: FakeDrive.new)
    assert_equal "def", backup.reload.folder_id
    assert_nil backup.problem
  end

  test "transferring ownership and deleting the ledger end the connection" do
    DriveBackup.create!(household: @home, connected_by: users(:alex), google_email: "a@example.com", refresh_token: "t")
    with_stub(DriveBackups::Oauth, :revoke, nil) do
      membership = @home.memberships.where.not(user: users(:alex)).first
      Accounts::OwnershipTransfer.call(household: @home, from: users(:alex), to_membership: membership)
      assert_nil @home.reload.drive_backup

      DriveBackup.create!(household: @home, connected_by: membership.user, google_email: "b@example.com", refresh_token: "t").files.create!(blob_id: 1, drive_file_id: "x")
      Households::Purge.call(@home, actor: membership.user)
      assert_equal 0, DriveBackup.where(household_id: @home.id).count
    end
  end
end
