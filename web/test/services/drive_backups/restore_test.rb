require "test_helper"

class DriveBackups::RestoreTest < ActiveSupport::TestCase
  setup do
    @old = households(:home)
    Categories::Seed.call(@old)
    water = @old.categories.find_by!(name_zh: "水費")
    @kept = @old.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "9月"), amount_required: 600, title: "Water")
    Photos::Upload.attach(@kept, [ photo_upload ])
    @backup = DriveBackup.create!(household: @old, connected_by: users(:alex), google_email: "alex@example.com", refresh_token: "token")
    @drive = FakeDrive.new
    DriveBackups::Run.call(@backup, client: @drive)

    # The disaster: a new, empty ledger with only the Drive
    @home = households(:parents)
    Categories::Seed.call(@home)
    @fresh = DriveBackup.create!(household: @home, connected_by: @home.owner, google_email: "alex@example.com", refresh_token: "token")
  end

  test "a fresh connection finds backups knowing nothing but the Drive" do
    found = DriveBackups::Scan.call(@drive).sole
    assert_equal @old.name, found["name"]
    assert_equal [ 1, 1 ], found.values_at("bills", "photos")
  end

  test "an empty CSV or a folder without one isn't offered" do
    @drive.create_folder("Empty", parent: @drive.find_folder(DriveBackups::Run::TOP_FOLDER))
    assert_equal 1, DriveBackups::Scan.call(@drive).size
  end

  test "the plan shows what would come back and changes no bills" do
    @home.records.delete_all
    plan = DriveBackups::Restore.plan(@fresh, DriveBackups::Scan.call(@drive).sole, client: @drive)
    assert_equal [ 1, 1, 1 ], [ plan.preview.rows.size, plan.photos, plan.matched ]
    assert_equal 0, @home.records.count
  end

  test "restores bills and photos, then backs up to the same folder without uploading them again" do
    @home.records.delete_all
    found = DriveBackups::Scan.call(@drive).sole
    plan = DriveBackups::Restore.plan(@fresh, found, client: @drive)
    Imports::Commit.call(plan.preview, user: @home.owner)
    @fresh.update!(folder_id: found["folder_id"], csv_file_id: found["csv_id"], restore_state: "running")
    assert_no_changes -> { @drive.files.size } do DriveBackups::Restore.call(@fresh, client: @drive) end

    restored = @home.records.sole
    assert_equal 1, restored.photos.count
    assert_equal "image/jpeg", restored.photos.first.content_type
    assert_equal [ "finished", 1, 1, 0 ], @fresh.reload.values_at(:restore_state, :restore_total, :restore_done, :restore_unmatched)

    assert_no_changes -> { @drive.named(/\.jpg\z/).size } do DriveBackups::Run.call(@fresh, client: @drive) end
    assert_equal found["folder_id"], @fresh.reload.folder_id
  end

  test "running it again after it stopped doesn't add a photo twice, and an unmatched photo stays in Drive" do
    @home.records.delete_all
    found = DriveBackups::Scan.call(@drive).sole
    Imports::Commit.call(DriveBackups::Restore.plan(@fresh, found, client: @drive).preview, user: @home.owner)
    year = @drive.folders.find { |_, f| f[:name] == "2026" }.first
    @drive.create_file("2026 9月 Gone app-999 1.jpg", StringIO.new("x"), content_type: "image/jpeg", parent: year)
    @fresh.update!(folder_id: found["folder_id"], restore_state: "running")
    2.times { DriveBackups::Restore.call(@fresh, client: @drive) }
    assert_equal 1, @home.records.sole.photos.count
    assert_equal 1, @fresh.reload.restore_unmatched
  end

  test "a backup job does nothing for an empty ledger that hasn't backed up" do
    @home.records.delete_all
    DriveBackups::Run.call(@fresh, client: fresh = FakeDrive.new)
    assert_empty fresh.folders
  end

  test "reads the bill ID from a photo's filename" do
    assert_equal "app-12", DriveBackups::Restore.key_of("2026 9月 AC cleaning app-12 1.jpg")
    assert_equal "74527", DriveBackups::Restore.key_of("2026 9月-10月 Water 74527 2.jpg")
  end
end
