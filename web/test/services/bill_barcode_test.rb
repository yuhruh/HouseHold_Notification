require "test_helper"

class BillBarcodeTest < ActiveSupport::TestCase
  test "tells the 3 barcodes apart in any order and reads deadline, biller, bill number and amount" do
    scan = Records::BillBarcode.parse(%w[0000Z1000002468 H123456789012345678 1512039ZZ])
    assert_equal Date.new(2026, 12, 3), scan.deadline
    assert_equal "9ZZ", scan.biller
    assert_equal "H123456789012345678", scan.bill_number
    assert_equal 2468, scan.amount
    assert_nil scan.billing_month, "0000 means the bill has no billing month"
  end

  test "a billing month in the 3rd barcode is read as 民國 YYMM" do
    scan = Records::BillBarcode.parse(%w[1411209ZY 98765432101234 1410AB000000880])
    assert_equal [ 2025, 10 ], [ scan.billing_year, scan.billing_month ]
    assert_equal 880, scan.amount
  end

  test "nothing unless all 3 are there and the deadline is a real date" do
    assert_nil Records::BillBarcode.parse(%w[1512039ZZ H123456789012345678])
    assert_nil Records::BillBarcode.parse(%w[1513409ZZ H123456789012345678 0000Z1000002468])
  end
end
