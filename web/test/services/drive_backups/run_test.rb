require "test_helper"

class DriveBackups::RunTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @bill = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "9月"), amount_required: 600, title: "Water")
    @bill.photos.attach(io: StringIO.new("jpeg-1"), filename: "a.jpg", content_type: "image/jpeg")
    @backup = DriveBackup.create!(household: @home, connected_by: users(:alex), google_email: "alex@example.com", refresh_token: "token")
    @drive = FakeDrive.new
  end

  def run_backup = DriveBackups::Run.call(@backup, client: @drive)

  test "saves the CSV and photos into the ledger's folder, sorted by year" do
    run_backup
    csv = @drive.named(/bills\.csv\z/).sole
    assert csv[:body].start_with?("\uFEFF"), "Excel needs the BOM"
    assert_includes csv[:body], "app-#{@bill.record_no}"
    assert_equal [ "Household Tracker Backup", @home.name ], @drive.path_of(csv[:parent])
    photo = @drive.named(/\.jpg\z/).sole
    assert_equal "jpeg-1", photo[:body]
    assert_includes photo[:name], "Water"
    assert_equal [ "Household Tracker Backup", @home.name, "Photos", "2026" ], @drive.path_of(photo[:parent])
    @backup.reload
    assert_equal [ 1, 1 ], [ @backup.bills_count, @backup.photos_count ]
    assert_not_nil @backup.last_backup_at
    assert_nil @backup.running_since
  end

  test "the next run replaces the CSV and uploads only new photos, and deleted bills stay in Drive" do
    run_backup
    @bill.photos.attach(io: StringIO.new("jpeg-2"), filename: "b.jpg", content_type: "image/jpeg")
    @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "10月"), amount_required: 700, title: "Later")
    run_backup
    assert_equal 1, @drive.named(/bills\.csv\z/).size
    assert_includes @drive.named(/bills\.csv\z/).sole[:body], "Later"
    assert_equal 2, @drive.named(/\.jpg\z/).size

    ActiveStorage::Attachment.where(record_id: @bill.id, record_type: "Record").delete_all
    assert_no_changes -> { @drive.files.size } do run_backup end
  end

  test "a folder removed in Drive is made again, with everything uploaded again" do
    run_backup
    @drive.gone << @backup.reload.folder_id
    @drive.folders.delete_if { |_, folder| folder[:name] == "Photos" }
    run_backup
    assert_equal 2, @drive.named(/\.jpg\z/).size
    assert_equal 1, @backup.reload.files.count
  end

  test "stops part way without losing what's done and frees the run" do
    second = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2025, "1月"), amount_required: 1, title: "Second")
    second.photos.attach(io: StringIO.new("x"), filename: "c.jpg", content_type: "image/jpeg")
    uploads = 0
    drive = @drive
    original = drive.method(:create_file)
    drive.define_singleton_method(:create_file) do |name, io, **options|
      next original.call(name, io, **options) if name.end_with?(".csv")
      raise DriveBackups::Client::StorageFull if (uploads += 1) > 1
      original.call(name, io, **options)
    end
    assert_raises(DriveBackups::Client::StorageFull) { run_backup }
    assert_equal 1, @backup.reload.files.count
    assert_nil @backup.running_since
  end

  test "a run already going is left alone, unless it died long ago" do
    @backup.update!(running_since: 5.minutes.ago)
    run_backup
    assert_empty @drive.files
    @backup.update!(running_since: 3.hours.ago)
    run_backup
    assert_not_empty @drive.files
  end
end
