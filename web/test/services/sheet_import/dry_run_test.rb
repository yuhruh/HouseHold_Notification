require "test_helper"

class SheetImport::DryRunTest < ActiveSupport::TestCase
  def run_dry(csv)
    result = SheetImport::Parser.new(csv, today: Date.new(2026, 10, 18)).call
    SheetImport::DryRun.call(result)
  end

  test "saves every clean row as a Record and rolls everything back" do
    assert_no_difference [ "Household.count", "Category.count", "Record.count" ] do
      result = run_dry(file_fixture("sheet_sample.csv").read)
      assert result.rows.none? { |row| row.errors.any? { |e| e.start_with?("Record:") } },
        result.rows.flat_map(&:errors).grep(/Record:/).inspect
    end
  end

  test "Record validations the parser doesn't check become row errors" do
    long_details = "x" * 201
    result = run_dry(file_fixture("sheet_sample.csv").read.sub("貸款抵押銀行：某銀行分行", long_details))

    row = result.rows.find { |r| r.details == long_details }
    assert row, "fixture row with long details"
    assert_includes row.errors, "Record: Details is too long (maximum is 200 characters)"
    assert_not result.ok?
  end
end
