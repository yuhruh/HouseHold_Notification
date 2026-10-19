require "test_helper"

class ImportsTest < ActionDispatch::IntegrationTest
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    sign_in_as users(:alex)
    @csv = file_fixture("sheet_sample.csv").read
  end

  def upload(csv = @csv)
    path = Rails.root.join("tmp", "import-#{SecureRandom.hex(4)}.csv")
    File.write(path, csv)
    post household_imports_path(@home), params: { file: Rack::Test::UploadedFile.new(path, "text/csv", original_filename: "記錄.csv") }
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def preview = @home.import_previews.order(:created_at).last

  def commit(choices = {})
    post commit_household_import_path(@home, preview), params: { choices: }
  end

  def import!(csv = @csv, choices = {})
    upload(csv)
    assert_redirected_to household_import_path(@home, preview)
    commit(choices)
    assert_redirected_to household_records_path(@home)
  end

  test "upload shows a preview and saves nothing; continue imports every row in one batch" do
    upload
    assert_redirected_to household_import_path(@home, preview)
    assert_empty @home.records
    assert_equal 12, preview.rows_of("new").size
    assert_equal [ [ "102", "103" ] ], preview.rows.select { |r| r["sheet_key"] != r["key"] }.map { |r| r.values_at("sheet_key", "key") }
    electricity = @home.categories.find_by!(record_type: "expense", name_zh: "電費")
    assert_equal electricity.id.to_s, preview.choices["categories"]["expense|台電電費"]

    get household_import_path(@home, preview)
    assert_response :success
    assert_select "select[name='choices[categories][expense|台電電費]']"
    assert_select "p.bg-amber-50", /300,000/, "the fixture is an excerpt, so its Total doesn't match"

    commit
    assert_redirected_to household_records_path(@home)
    assert_equal 12, @home.records.count
    assert_equal 12, @home.import_keys.count
    batch = @home.import_batches.sole
    assert_equal [ 12, 0, 0 ], [ batch.created_count, batch.updated_count, batch.unchanged_count ]
    assert_equal BigDecimal("74527"), @home.records.sum(:amount_paid)
    assert_equal electricity, @home.category_aliases.find_by!(alias: "台電電費").category
    assert_equal "電費", @home.records.find_by!(import_key: "101").title
    assert_equal 12, RecordEvent.where(household: @home, action: "import_created").count
  end

  test "re-importing the same file creates 0 and updates 0; changing one amount updates exactly that record" do
    import!
    upload
    assert_equal 12, preview.rows_of("unchanged").size
    assert_equal "103", preview.rows.find { |r| r["sheet_key"] != r["key"] }["key"], "the repeated ID keeps the ID it got last time"
    commit
    assert_equal [ 0, 0, 12 ], @home.import_batches.order(:id).last.values_at(:created_count, :updated_count, :unchanged_count)

    import!(@csv.sub("水費,水費,612,612", "水費,水費,575,575"))
    batch = @home.import_batches.order(:id).last
    assert_equal [ 0, 1 ], [ batch.created_count, batch.updated_count ]
    assert_equal BigDecimal("575"), @home.records.find_by!(import_key: "79").amount_paid
  end

  test "a field changed in both the app and the sheet is a conflict; keeping the app's value is honoured" do
    import!
    record = @home.records.find_by!(import_key: "100")
    record.update!(payment_note: "app note")
    upload(@csv.sub("15,600\",2026/5/30,玉山ubear", "15,600\",2026/5/30,sheet note"))
    change = preview.rows_of("update").sole["fields"].sole
    assert change["conflict"]
    line = preview.rows_of("update").sole["line"]
    commit(conflicts: { "#{line}-payment_note" => "app" })
    assert_equal "app note", record.reload.payment_note
  end

  test "rows whose records were deleted in the app are skipped unless re-created" do
    import!
    record = @home.records.find_by!(import_key: "78")
    delete household_record_path(@home, record)
    upload
    deleted = preview.rows_of("deleted").sole
    assert_equal "78", deleted["key"]
    commit
    assert_not @home.records.exists?(import_key: "78")

    upload
    commit(deleted: { deleted["line"].to_s => "recreate" })
    assert @home.records.exists?(import_key: "78")
  end

  test "a file with errors fails with the rows listed and saves nothing" do
    upload(@csv.sub("NT$680,NT$680", "NT$680,NT$900"))
    assert_response :unprocessable_content
    assert_select "td", text: "78"
    assert_empty @home.records
    assert_empty @home.import_previews
  end

  test "undo removes the latest batch and frees its IDs" do
    import!
    batch = @home.import_batches.sole
    post undo_household_import_path(@home, batch)
    assert_redirected_to new_household_import_path(@home)
    assert_empty @home.records
    assert_empty @home.import_keys
    assert batch.reload.undone_at
    upload
    assert_equal 12, preview.rows_of("new").size
  end

  test "undo restores the values an import updated" do
    import!
    import!(@csv.sub("水費,水費,612,612", "水費,水費,575,575"))
    first, second = @home.import_batches.order(:id).to_a
    assert_not first.undoable?, "only the latest active batch is undoable"
    post undo_household_import_path(@home, first)
    assert_redirected_to new_household_import_path(@home)
    assert_nil first.reload.undone_at
    post undo_household_import_path(@home, second)
    assert_equal BigDecimal("612"), @home.records.find_by!(import_key: "79").amount_paid
    assert first.reload.undoable?
  end

  test "undo is refused once a record from the import was edited or deleted" do
    import!
    batch = @home.import_batches.sole
    patch household_record_path(@home, @home.records.find_by!(import_key: "79")),
      params: { record: { details: "edited", lock_version: @home.records.find_by!(import_key: "79").lock_version } }
    assert batch.undo_blocked?
    post undo_household_import_path(@home, batch)
    assert_redirected_to new_household_import_path(@home)
    assert_nil batch.reload.undone_at
    assert_equal 12, @home.records.count
  end

  test "records changed after the preview stop the commit" do
    import!
    upload(@csv.sub("水費,水費,612,612", "水費,水費,575,575"))
    @home.records.find_by!(import_key: "79").update!(details: "edited meanwhile")
    commit
    assert_response :unprocessable_content
    assert_equal BigDecimal("612"), @home.records.find_by!(import_key: "79").amount_paid
  end

  test "maintenance chains: only the latest row keeps the next-due date, and a stale one is cleared" do
    upload
    chain = preview.choices["chains"].find { |c| c["category"] == "冷氣清洗" }
    assert_equal "clear", chain["action"], "next due 2026-07-03 passed more than 30 days ago"
    commit(chains: { preview.choices["chains"].index(chain).to_s => { action: "new_date", new_date: "2026-12-01" } })
    assert_equal Date.new(2026, 12, 1), @home.records.find_by!(import_key: "95").next_due_on
    filters = @home.records.find_by!(import_key: "96")
    assert_nil filters.next_due_on, "Next Time: October isn't a date"
  end

  test "viewers can't import" do
    sign_out
    sign_in_as users(:google_only)
    get new_household_import_path(@home)
    assert_response :forbidden
    upload
    assert_response :forbidden
  end
end
