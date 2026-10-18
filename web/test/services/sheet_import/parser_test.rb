require "test_helper"

class SheetImport::ParserTest < ActiveSupport::TestCase
  setup do
    @result = SheetImport::Parser.new(file_fixture("sheet_sample.csv").read, today: Date.new(2026, 10, 18)).call
    @rows = @result.rows.index_by(&:line)
  end

  def row(id) = @result.rows.find { |r| r.id == id.to_s }

  test "finds the header below the summary rows and parses every data row" do
    assert_empty @result.file_errors
    assert_equal 12, @result.rows.size
  end

  test "reads the sheet's Total cell above the header" do
    assert_equal BigDecimal("300000"), @result.sheet_total
  end

  test "dry-run report compares the sheet Total with Paid" do
    report = SheetImport::DryRunReport.new(@result, today: Date.new(2026, 10, 18)).to_s
    # The fixture is a 12-row excerpt, so its Paid can't reach the full sheet's Total.
    assert_includes report, "Sheet Total 300000 ≠ Paid 74527 (difference 225473)"

    csv = file_fixture("sheet_sample.csv").read.sub('"300,000"', '"74,527"')
    matching = SheetImport::Parser.new(csv, today: Date.new(2026, 10, 18)).call
    assert_includes SheetImport::DryRunReport.new(matching, today: Date.new(2026, 10, 18)).to_s, "Sheet Total 74527 = Paid ✓"
  end

  test "✅ rule: complete Expense/Tax rows are paid" do
    assert_equal :paid, row(78).status
    assert_equal BigDecimal("680"), row(78).paid
    assert_equal :paid, row(88).status
    assert_equal :paid, row(98).status, "全年 row with Finished Date and Paid = Required is ✅"
    assert_equal Date.new(2026, 1, 28), row(98).finished_on
  end

  test "✅ in sheet but Paid < Required is imported as ❌ partial with a warning" do
    r = row(101)
    assert_equal :partial, r.status
    assert r.warnings.any? { |w| w.include?("imported as ❌") }
  end

  test "category suggestions merge item variants and require details for 保險" do
    assert_equal "電費", row(101).category.name
    assert_equal "保險", row(99).category.name
    assert row(99).errors.empty?, "保險 row has Detailed filled"
  end

  test "year boundary row gets end year + 1" do
    r = @result.rows.find { |x| x.period&.start_month == 12 }
    assert_equal [ 2025, 12, 2026, 1 ], r.period.deconstruct
  end

  test "repeated ID gets the next unused ID" do
    assert_equal [ { line: 17, old_id: "102", new_id: "103" } ], @result.id_reassignments
  end

  test "maintenance chains are keyed by category and room" do
    keys = @result.chains.map { |c| [ c.category, c.details_key ] }
    assert_includes keys, [ "冷氣清洗", "主臥、客廳、書房、次臥".split("、").sort.join("、") ]
    assert_includes keys, [ "濾網/濾芯更換", "主臥、客廳、書房、次臥".split("、").sort.join("、") ]
    assert_includes keys, [ "濾網/濾芯更換", "全戶" ]
    assert_equal Date.new(2026, 7, 3), row(95).next_due_on
    assert row(96).warnings.any? { |w| w.include?("Next Time") }
  end

  test "missing ID column is a file error" do
    csv = file_fixture("sheet_sample.csv").read.sub("ID,,Type", "X,,Type")
    result = SheetImport::Parser.new(csv).call
    assert result.file_errors.any? { |e| e.include?("Missing ID column") }
  end

  test "errors: Paid > Required, Paid without Finished Date, missing 牌照稅 plate" do
    csv = <<~CSV
      ID,,Type,year,month,,Detailed,Required,Paid,Finished Date,
      1,TRUE,Expense,2026,1月,水費,水費,500,600,2026/2/1,
      2,FALSE,Expense,2026,1月,水費,水費,500,500,,
      3,TRUE,Tax,2026,全年,牌照稅,,450,450,2026/5/1,
    CSV
    rows = SheetImport::Parser.new(csv, today: Date.new(2026, 10, 18)).call.rows
    assert rows[0].errors.any? { |e| e.include?("more than Required") }
    assert rows[1].errors.any? { |e| e.include?("Finished Date is empty") }
    assert rows[2].errors.any? { |e| e.include?("車牌號碼") }
  end
end
