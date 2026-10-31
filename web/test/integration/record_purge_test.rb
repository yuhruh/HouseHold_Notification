require "test_helper"

class RecordPurgeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @water = @home.categories.find_by!(name_zh: "水費")
    @bill = @home.records.create!(record_type: "expense", category: @water, period: Period.parse(2026, "1月-2月"), amount_required: 600)
    RecordEvent.log!(@bill, :created, user: users(:alex))
    @bill.photos.attach(io: StringIO.new("jpeg"), filename: "receipt.jpg", content_type: "image/jpeg")
    batch = @home.import_batches.create!(created_by: users(:alex), filename: "sheet.csv")
    @home.import_keys.create!(key: "1", record: @bill, import_batch: batch)
    @template = @home.recurring_templates.create!(category: @water, interval_months: 2, anchor_month: 1, starts_on: Date.new(2026, 1, 1),
      due_day: 15, due_month_offset: 2, lead_days: 7, default_amount: 580)
    sign_in_as users(:alex)
    reauthenticate!
  end

  test "the owner deletes every record, the import history and the templates; the rest stays" do
    other = households(:parents).records.count
    categories = @home.categories.count
    post household_record_purge_path(@home), params: { confirm_name: @home.name, delete_templates: "1" }
    assert_redirected_to household_records_path(@home)
    assert_equal 0, @home.records.count
    assert_equal 0, @home.recurring_templates.count
    assert_equal 0, ImportBatch.where(household: @home).count
    assert_equal 0, ImportKey.where(household: @home).count
    assert_equal 0, RecordEvent.where(household: @home).count
    assert_equal categories, @home.categories.count
    assert_equal other, households(:parents).records.count
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "Record").count
    assert_enqueued_jobs 1, only: Photos::PurgeBlobsJob
    event = SecurityEvent.find_by!(kind: "records_deleted", household_id: @home.id)
    assert_equal 1, event.metadata["count"]
  end

  test "kept templates restart this month instead of recreating past bills" do
    post household_record_purge_path(@home), params: { confirm_name: @home.name, delete_templates: "0" }
    @template.reload
    assert_equal Time.use_zone(users(:alex).time_zone) { Date.current }.beginning_of_month, @template.starts_on
    assert_equal 1, @template.anchor_month, "the billing rhythm is unchanged"
  end

  test "a wrong name deletes nothing" do
    post household_record_purge_path(@home), params: { confirm_name: "nope", delete_templates: "1" }
    assert_redirected_to new_household_record_purge_path(@home)
    assert_equal 1, @home.records.count
  end

  test "only the owner gets the page" do
    get new_household_record_purge_path(@home)
    assert_response :success
    assert_select "input[name=delete_templates][checked]"
    sign_out
    sign_in_as users(:google_only) # a viewer in this household
    reauthenticate!
    post household_record_purge_path(@home), params: { confirm_name: @home.name }
    assert_equal 1, @home.records.count
  end
end
