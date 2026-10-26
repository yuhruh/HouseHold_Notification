module Records
  # The three convenience-store barcodes on a Taiwan bill (三段式條碼), told apart by their shape:
  #   1st: payment deadline as 民國 YYMMDD + the biller code ("1512036AM" → 2026-12-03, "6AM")
  #   2nd: the bill number (銷帳編號), unique to the bill
  #   3rd: billing year-month as 民國 YYMM + 2 check characters + the amount in 9 digits
  #        ("1410AB000000880" → 2025-10, 880). Tax bills put other digits there ("0003A0000001563":
  #        not 2011-03), so it's a billing month only when its year is the deadline's or the one before
  # The phone reads them (bill_scan_controller.js); this is the authority on what they mean.
  class BillBarcode
    FIRST = /\A(\d{6})([0-9A-Z]{3})\z/
    THIRD = /\A(\d{4})[0-9A-Z]{2}(\d{9})\z/
    SECOND = /\A[0-9A-Z]{6,20}\z/

    attr_reader :deadline, :biller, :bill_number, :amount, :billing_year, :billing_month

    # nil unless all three barcodes are there and make sense
    def self.parse(codes)
      codes = Array(codes).map { it.to_s.strip.upcase }.uniq
      first = codes.find { FIRST.match?(it) && date(it[0, 6]) }
      third = codes.find { THIRD.match?(it) }
      second = codes.find { it != first && it != third && SECOND.match?(it) }
      new(first, second, third) if first && second && third
    end

    # 民國 YYMMDD with a two-digit year: 15 → 115 → 2026
    def self.date(yymmdd)
      Date.new(2011 + yymmdd[0, 2].to_i, yymmdd[2, 2].to_i, yymmdd[4, 2].to_i)
    rescue Date::Error
      nil
    end

    def initialize(first, second, third)
      @deadline = self.class.date(first[0, 6])
      @biller = first[6, 3]
      @bill_number = second
      @amount = third[-9..].to_i
      year, month = 2011 + third[0, 2].to_i, third[2, 2].to_i
      @billing_year, @billing_month = year, month if (1..12).cover?(month) && ((@deadline.year - 1)..@deadline.year).cover?(year)
    end
  end
end
