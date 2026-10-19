require "csv"

module Records
  # CSV in the 記錄 tab's layout (PRD → Sheet cutover), so an export re-imports unchanged: the Total
  # row above the header, then ID, ✅, Type, year, month, Item, Detailed, Required, Paid,
  # Finished Date, Note. Records entered in the app have no sheet ID and export as "app-<record_no>".
  class CsvExport
    HEADER = [ "ID", "✅", "Type", "year", "month", "Item", "Detailed", "Required", "Paid", "Finished Date", "Note" ].freeze

    def initialize(records)
      @records = records
    end

    def to_csv
      records = @records.sort_by { |r| [ Integer(r.import_key.to_s, exception: false) || Float::INFINITY, r.record_no ] }
      CSV.generate do |csv|
        totals = records.group_by(&:currency).transform_values { |list| list.sum { |r| r.amount_paid || 0 } }
        csv << [ nil, "Total", amount(totals.fetch("TWD", 0), "TWD"), *([ nil ] * 8) ]
        csv << HEADER
        records.each { |record| csv << row(record) }
      end
    end

    def self.app_key(record) = "app-#{record.record_no}"

    private

    def row(record)
      [
        record.import_key || self.class.app_key(record), record.settled ? "TRUE" : "FALSE", record.record_type.capitalize,
        record.period_year, month(record), record.import_snapshot&.dig("item") || record.title, record.details,
        amount(record.amount_required, record.currency), amount(record.amount_paid, record.currency),
        record.paid_on&.strftime("%Y/%-m/%-d"), record.payment_note
      ]
    end

    def month(record)
      start, finish = record.period_start_month, record.period_end_month
      if start == 1 && finish == 12 && record.period_end_year == record.period_year then "全年"
      elsif start == finish && record.period_end_year == record.period_year then "#{start}月"
      else "#{start}月-#{finish}月"
      end
    end

    def amount(value, currency)
      return nil if value.nil?
      text = value.to_d.frac.zero? ? value.to_i.to_s : value.to_d.to_s("F")
      currency == "USD" ? "US$#{text}" : text
    end
  end
end
