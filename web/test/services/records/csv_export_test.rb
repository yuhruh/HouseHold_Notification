require "test_helper"

class Records::CsvExportTest < ActiveSupport::TestCase
  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @user = users(:alex)
  end

  def import(csv)
    preview, failed = Imports::Planner.new(household: @home, user: @user, csv:, filename: "x.csv", today: Date.new(2026, 10, 18)).call
    assert_nil failed, failed&.error_rows&.map(&:errors).inspect
    preview
  end

  test "an export of imported records re-imports with nothing new and nothing changed" do
    Imports::Commit.call(import(file_fixture("sheet_sample.csv").read), user: @user)
    csv = Records::CsvExport.new(@home.records.to_a).to_csv
    preview = import(csv)
    assert_equal({ "unchanged" => 12 }, preview.rows.group_by { |r| r["kind"] }.transform_values(&:size))
    assert_includes csv.lines.first, "74527"
  end

  test "records entered in the app export with an app- ID and USD amounts keep their currency" do
    water = @home.categories.find_by!(name_zh: "水費")
    record = @home.records.create!(record_type: "expense", category: water, period: Period.parse(2025, "12月-1月"),
      currency: "USD", amount_required: 12.5, amount_paid: 12.5, paid_on: Date.new(2026, 1, 3))
    row = CSV.parse(Records::CsvExport.new([ record ]).to_csv)[2]
    assert_equal [ "app-#{record.record_no}", "TRUE", "Expense", "2025", "12月-1月", "水費" ], row.first(6)
    assert_equal [ "US$12.5", "US$12.5", "2026/1/3" ], row[7, 3]
  end

  test "records entered in the app round-trip by their app- ID instead of being imported twice" do
    water = @home.categories.find_by!(name_zh: "水費")
    record = @home.records.create!(record_type: "expense", category: water, period: Period.parse(2026, "3月-4月"), amount_required: 600)
    csv = Records::CsvExport.new([ record ]).to_csv
    assert_equal "unchanged", import(csv).rows.sole["kind"]

    preview = import(csv.sub(",600,", ",650,"))
    row = preview.rows.sole
    assert_equal [ "update", record.id ], row.values_at("kind", "record_id")
    assert_equal [ [ "amount_required", "600.0", "650.0" ] ], row["fields"].map { |f| f.values_at("field", "base", "sheet") }
    Imports::Commit.call(preview, user: @user)
    assert_equal BigDecimal("650"), record.reload.amount_required
    assert_equal 1, @home.records.count
  end
end
