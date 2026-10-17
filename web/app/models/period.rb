# A billing period: start (year, month) .. end (year, month). Plain value object.
#
# Year boundary rule (PRD → Import mapping): end year = year + 1 when the end month is
# before the start month, so "2025 · 12月–1月" runs from 2025-12 to 2026-01.
Period = Data.define(:start_year, :start_month, :end_year, :end_month)

class Period
  class ParseError < StandardError; end

  RANGE = /\A(\d{1,2})\s*月\s*[-–—~～至]\s*(\d{1,2})\s*月\z/
  SINGLE = /\A(\d{1,2})\s*月\z/
  FULL_YEAR = /\A(全年|整年)\z/

  def self.parse(year, text)
    year = Integer(year.to_s.strip, exception: false) or raise ParseError, "year #{year.inspect} is not a number"
    raise ParseError, "year #{year} is out of range" unless (2000..2100).cover?(year)

    normalized = text.to_s.unicode_normalize(:nfkc).strip
    case normalized
    when FULL_YEAR then from_months(year, 1, 12)
    when RANGE then from_months(year, $1.to_i, $2.to_i)
    when SINGLE then from_months(year, $1.to_i, $1.to_i)
    else raise ParseError, "month #{text.inspect} is not recognized (expected e.g. 1月-2月, 7月, 全年)"
    end
  end

  def self.from_months(year, start_month, end_month)
    [ start_month, end_month ].each do |m|
      raise ParseError, "month #{m} is not between 1 and 12" unless (1..12).cover?(m)
    end
    end_year = end_month < start_month ? year + 1 : year
    new(start_year: year, start_month: start_month, end_year: end_year, end_month: end_month)
  end

  def month_count
    (end_year * 12 + end_month) - (start_year * 12 + start_month) + 1
  end

  def to_s
    if start_month == 1 && end_month == 12 && start_year == end_year
      "#{start_year} 全年"
    elsif start_year == end_year && start_month == end_month
      "#{start_year} #{start_month}月"
    elsif start_year == end_year
      "#{start_year} #{start_month}月-#{end_month}月"
    else
      "#{start_year}-#{start_month}月 – #{end_year}-#{end_month}月"
    end
  end
end
