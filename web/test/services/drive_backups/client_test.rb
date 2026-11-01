require "test_helper"

class DriveBackups::ClientTest < ActiveSupport::TestCase
  test "builds the real Google service with the Drive scope" do
    drive = DriveBackups::Client.new("token").instance_variable_get(:@drive)
    assert_kind_of Google::Apis::DriveV3::DriveService, drive
    assert_includes Array(drive.authorization.scope), DriveBackups::Oauth::SCOPE
  end

  test "lost access and a full Drive become errors a run understands" do
    client = DriveBackups::Client.new("token")
    drive = client.instance_variable_get(:@drive)
    drive.define_singleton_method(:get_about) { |**| raise Signet::AuthorizationError.new("invalid_grant") }
    assert_raises(DriveBackups::Client::NeedsReconnect) { client.email }
    drive.define_singleton_method(:create_file) { |*, **| raise Google::Apis::ClientError.new("storageQuotaExceeded: full", status_code: 403) }
    assert_raises(DriveBackups::Client::StorageFull) { client.create_folder("x") }
    drive.define_singleton_method(:get_file) { |*, **| raise Google::Apis::ClientError.new("notFound", status_code: 404) }
    assert_not client.exists?("gone")
  end
end
