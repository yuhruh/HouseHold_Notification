require "test_helper"

class BillScansTest < ActionDispatch::IntegrationTest
  CODES = %w[1512039ZZ H123456789012345678 0000Z1000002468].freeze

  setup do
    @home = households(:home)
    Categories::Seed.call(@home)
    @tax = @home.categories.find_by!(record_type: "tax")
    sign_in_as users(:alex)
  end

  def scan(codes = CODES) = get(household_bill_scan_path(@home), params: { codes: }, as: :json)

  test "New Record shows the Scan the Bill's Barcodes card above the form" do
    get new_household_record_path(@home)
    assert_select "[data-controller=bill-scan] [data-action='bill-scan#open']", /掃描條碼/
    assert_select "input[type=hidden][name='record[bill_number]']"
  end

  test "a new biller is unknown until the household says what it is; then the form values come back" do
    scan
    body = response.parsed_body
    assert_equal [ true, false, 2468, "2026-12-03", "9ZZ" ], body.values_at("ok", "known", "amount", "deadline", "biller")
    assert_nil body["due_on"]

    post household_biller_codes_path(@home), params: { code: "9ZZ", category_id: @tax.id, deadline_offset_days: 3 }
    assert_response :no_content
    scan
    body = response.parsed_body
    assert_equal [ true, @tax.id, "2026-11-30", 2026 ], body.values_at("known", "category_id", "due_on", "period_year")
    assert_nil body["period_months"]

    @home.records.create!(record_type: "tax", category: @tax, period: Period.parse(2025, "全年"))
    scan
    assert_equal [ 1, 12 ], response.parsed_body["period_months"], "no billing month: the months of the category's latest record"
  end

  test "a bill already recorded (same bill number) is flagged; unreadable scans are refused" do
    record = @home.records.create!(record_type: "tax", category: @tax, period: Period.parse(2026, "全年"), bill_number: CODES[1])
    scan
    assert_equal household_record_path(@home, record), response.parsed_body.dig("duplicate", "url")
    scan(%w[1512039ZZ])
    assert_response :unprocessable_content
  end

  test "saving a scanned record keeps its bill number; viewers can't scan or teach billers" do
    post household_records_path(@home), params: { record: { category_id: @tax.id, period_year: 2026, period_start_month: 1, period_end_month: 12,
      currency: "TWD", amount_required: "2468", due_on: "2026-11-30", reminder_frequency: "none", bill_number: CODES[1] } }
    assert_equal CODES[1], @home.records.order(:id).last.bill_number

    sign_out
    sign_in_as users(:google_only)
    scan
    assert_response :forbidden
    post household_biller_codes_path(@home), params: { code: "9ZZ", category_id: @tax.id }
    assert_response :forbidden
  end
end
