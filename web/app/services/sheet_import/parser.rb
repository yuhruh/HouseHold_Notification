require "csv"

module SheetImport
  # Parses a CSV export of the 記錄 tab into rows with errors and warnings. Writes nothing.
  # Used by `bin/rails import:dry_run` (M0) and later by the import preview (M2).
  class Parser
    TYPES = { "expense" => :expense, "maintenance" => :maintenance, "tax" => :tax }.freeze
    DONE_VALUES = %w[true ✅ ✓ ✔ v y yes 1].freeze
    NEXT_TIME = /next\s*time\s*[:：]\s*(\S+)/i
    STALE_CHAIN_DAYS = 30

    Row = Struct.new(:line, :id, :done_in_sheet, :record_type, :period, :item, :category, :details,
                     :required, :paid, :currency, :finished_on, :note, :next_due_on, :status,
                     :errors, :warnings, keyword_init: true) do
      def error(message) = errors << message
      def warn(message) = warnings << message
    end

    Chain = Struct.new(:category, :details_key, :rows, keyword_init: true) do
      def latest = rows.select(&:finished_on).max_by(&:finished_on) || rows.last
      def next_due_on = latest&.next_due_on
    end

    Result = Struct.new(:file_errors, :rows, :id_reassignments, :chains, keyword_init: true) do
      def error_rows = rows.select { |r| r.errors.any? }
      def warning_rows = rows.select { |r| r.warnings.any? }
      def ok? = file_errors.empty? && error_rows.empty?
    end

    def initialize(csv_text, today: Date.current)
      @csv_text = csv_text.to_s.sub(/\A﻿/, "")
      @today = today
    end

    def call
      table = CSV.parse(@csv_text)
      header_index = table.index { |cells| header_row?(cells) }
      return Result.new(file_errors: [ "Header row not found (expected columns Type, year, month)" ], rows: [], id_reassignments: [], chains: []) unless header_index

      columns, file_errors = map_columns(table[header_index])
      return Result.new(file_errors: file_errors, rows: [], id_reassignments: [], chains: []) if file_errors.any?

      rows = table.each_with_index.drop(header_index + 1).filter_map do |cells, index|
        next if cells.compact.all? { |c| c.to_s.strip.empty? }
        parse_row(cells, index + 1, columns)
      end

      Result.new(file_errors: [], rows: rows, id_reassignments: reassign_ids(rows), chains: build_chains(rows))
    end

    private

    def header_row?(cells)
      names = cells.map { |c| c.to_s.strip.downcase }
      names.include?("type") && names.include?("year") && names.include?("month")
    end

    # Named columns by header; unnamed ones by position next to known columns (as in the sheet).
    def map_columns(header)
      names = header.map { |c| c.to_s.unicode_normalize(:nfkc).strip.downcase }
      errors = []
      names.reject(&:empty?).tally.each { |name, count| errors << "Duplicate column \"#{name}\" (#{count} times)" if count > 1 }

      find = ->(*candidates) { names.index { |n| candidates.include?(n) } }
      columns = {
        id: find.("id"),
        type: find.("type"),
        year: find.("year"),
        month: find.("month"),
        details: find.("detailed", "details", "detail"),
        required: find.("required"),
        paid: find.("paid"),
        finished: find.("finished date", "finished")
      }
      columns[:item] = find.("item", "項目") || (columns[:month] && names[columns[:month] + 1].to_s.empty? ? columns[:month] + 1 : nil)
      columns[:done] = find.("done", "✅") || (columns[:type] && columns[:type].positive? && names[columns[:type] - 1].to_s.empty? ? columns[:type] - 1 : nil)
      columns[:note] = find.("note", "備註") || (columns[:finished] && names[columns[:finished] + 1].to_s.empty? ? columns[:finished] + 1 : nil)

      errors << "Missing ID column. Add an ID column to the sheet once (1, 2, 3… pasted as values)." unless columns[:id]
      %i[type year month item required paid finished].each { |key| errors << "Missing column: #{key}" unless columns[key] }
      [ columns, errors ]
    end

    def parse_row(cells, line, columns)
      cell = ->(key) { columns[key] ? cells[columns[key]].to_s.strip : "" }
      row = Row.new(line: line, errors: [], warnings: [], id: cell.(:id), item: cell.(:item),
                    details: cell.(:details).presence, note: cell.(:note).presence,
                    done_in_sheet: DONE_VALUES.include?(cell.(:done).downcase))

      row.error("ID is blank") if row.id.empty?
      row.record_type = TYPES[cell.(:type).downcase] or row.error("Type #{cell.(:type).inspect} must be Expense, Maintenance or Tax")
      begin
        row.period = Period.parse(cell.(:year), cell.(:month))
      rescue Period::ParseError => e
        row.error(e.message)
      end
      row.error("Item is blank") if row.item.empty?

      parse_amounts(row, cell.(:required), cell.(:paid))
      parse_finished(row, cell.(:finished))
      row.category = CategorySuggester.suggest(row.item, row.record_type) unless row.item.empty?
      if row.category&.detail_required && row.details.blank?
        row.error("#{row.category.name} needs #{row.category.detail_label} in Detailed")
      end
      parse_next_time(row)
      apply_done_rule(row) if row.errors.empty?
      row
    end

    def parse_amounts(row, required_text, paid_text)
      currencies = []
      { required: required_text, paid: paid_text }.each do |field, text|
        amount, currency = AmountParser.parse(text)
        row[field] = amount
        currencies << currency if currency
      rescue AmountParser::ParseError => e
        row.error("#{field.to_s.capitalize}: #{e.message}")
      end
      if currencies.uniq.size > 1
        row.error("Required and Paid use different currencies")
      else
        row.currency = currencies.first || "TWD"
      end
      row.warn("TWD amount has cents") if row.currency == "TWD" && [ row.required, row.paid ].compact.any? { |a| a.frac.nonzero? }
    end

    def parse_finished(row, text)
      row.finished_on = DateParser.parse(text)
      row.error("Finished Date #{row.finished_on} is in the future") if row.finished_on && row.finished_on > @today
    rescue DateParser::ParseError => e
      row.error("Finished Date: #{e.message}")
    end

    def parse_next_time(row)
      return unless row.note && (match = row.note.match(NEXT_TIME))
      row.next_due_on = DateParser.parse(match[1])
    rescue DateParser::ParseError
      row.warn("Next Time #{match[1].inspect} isn't a date; kept in the note")
    end

    # PRD §1 status rules / Import mapping "✅ done column". The app's ✅ is derived, never trusted.
    def apply_done_rule(row)
      required, paid, finished = row.required, row.paid, row.finished_on
      row.error("Paid #{fmt(paid)} is more than Required #{fmt(required)}") if required && paid && paid > required
      row.error("Paid is filled but Finished Date is empty") if paid&.positive? && finished.nil?

      if row.record_type == :maintenance
        row.status = finished && (required.nil? || paid == required) ? :paid : (finished && paid ? :partial : :unpaid)
      else
        row.error("Finished Date is filled but Paid is empty") if finished && required && paid.nil?
        row.error("Finished Date is filled but Required is empty") if finished && required.nil?
        row.status =
          if finished && required && paid == required then :paid
          elsif finished && paid then :partial
          else :unpaid
          end
      end
      return if row.errors.any?

      if row.done_in_sheet && row.status != :paid
        reason = finished.nil? ? "Finished Date is empty" : "Paid #{fmt(paid)} < Required #{fmt(required)}"
        row.warn("✅ in sheet, but #{reason} → imported as ❌")
      elsif !row.done_in_sheet && row.status == :paid
        row.warn("Not ✅ in sheet, but complete → imported as ✅")
      end
    end

    # Reused IDs get the next unused ID (PRD §9 "Every ID is unique and never reused").
    def reassign_ids(rows)
      used = rows.map(&:id).reject(&:empty?)
      next_id = (used.filter_map { |id| Integer(id, exception: false) }.max || 0) + 1
      seen = {}
      rows.reject { |r| r.id.empty? }.filter_map do |row|
        if seen[row.id]
          new_id = next_id.to_s
          next_id += 1
          { line: row.line, old_id: row.id, new_id: new_id }
        else
          seen[row.id] = true
          nil
        end
      end
    end

    # Maintenance chains keyed by (category, normalized details / room), PRD → Maintenance chains.
    def build_chains(rows)
      rows.select { |r| r.record_type == :maintenance && r.category }
          .group_by { |r| [ r.category.name, details_key(r.details) ] }
          .map do |(category, key), chain_rows|
            chain = Chain.new(category: category, details_key: key, rows: chain_rows.sort_by { |r| r.finished_on || Date.new(1900) })
            chain_rows.first.warn("No room/area in Detailed; this chain can't be told apart from other units") if key.empty?
            chain
          end
    end

    def details_key(details)
      details.to_s.unicode_normalize(:nfkc).split(/[、,，\/;；]+/).map(&:strip).reject(&:empty?).sort.join("、")
    end

    def fmt(amount) = amount&.to_s("F")&.delete_suffix(".0")
  end
end
