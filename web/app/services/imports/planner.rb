module Imports
  # Upload → preview (PRD §9 import flow): parse, validate every row as a Record (dry-run #2), then
  # classify each row by sheet ID only: new, update (three-way per field, ⚠ only when both the app
  # and the sheet changed a field), unchanged, or deleted in the app. Nothing is written except the
  # ImportPreview. Returns [preview, nil] or [nil, parser_result_with_errors].
  class Planner
    STALE_CHAIN_DAYS = SheetImport::Parser::STALE_CHAIN_DAYS

    def initialize(household:, user:, csv:, filename:, today: Date.current)
      @household, @user, @csv, @filename, @today = household, user, csv, filename, today
    end

    def call
      result = SheetImport::Parser.new(@csv, today: @today).call
      SheetImport::DryRun.call(result)
      return [ nil, result ] unless result.ok?

      prepared = result.rows.to_h do |row|
        values = SheetRow.from_parser(row)
        [ row.line, [ values, SheetRow.digest(row.record_type.to_s, values) ] ]
      end
      keys = assign_keys(result.rows, prepared)
      import_keys = @household.import_keys.includes(:record).where(key: keys.values).index_by(&:key)
      app_records = app_records_for(keys.values)
      versions = {}
      rows = result.rows.map do |row|
        key = keys.fetch(row.line)
        values, digest = prepared.fetch(row.line)
        entry = { "line" => row.line, "key" => key, "sheet_key" => row.id, "record_type" => row.record_type.to_s,
                  "values" => values, "digest" => digest, "warnings" => row.warnings,
                  "suggested_category" => row.category.name }
        classify(entry, import_keys[key], versions, app_records[key])
      end

      preview = @household.import_previews.create!(
        user: @user, filename: @filename, csv_sha256: Digest::SHA256.hexdigest(@csv), rows:, record_versions: versions,
        choices: { "categories" => category_suggestions(rows), "chains" => chains(result, rows), "conflicts" => {}, "deleted" => {},
                   "payment_keywords" => payment_keywords(rows),
                   "sheet_total" => SheetRow.decimal(result.sheet_total) },
        expires_at: ImportPreview::TTL.from_now
      )
      [ preview, nil ]
    end

    private

    # Repeated IDs get the next ID unused in both the file and the household (PRD §9). A repeat that
    # an earlier import already gave a new ID (not pasted back yet) gets that same ID again: the one
    # whose record still matches the row, else any not used elsewhere in this file.
    def assign_keys(rows, prepared)
      file_ids = rows.map(&:id)
      reassigned = @household.import_keys.where(source_key: file_ids).includes(:record).group_by(&:source_key)
      used = file_ids + @household.import_keys.pluck(:key)
      next_id = (used.filter_map { |id| Integer(id, exception: false) }.max || 0) + 1
      taken = file_ids.to_set
      seen = {}
      rows.to_h do |row|
        key = row.id
        if seen[row.id]
          candidates = reassigned.fetch(row.id, []).reject { |k| taken.include?(k.key) }
          earlier = candidates.find { |k| k.record&.import_digest == prepared[row.line].last } || candidates.first
          if earlier
            key = earlier.key
          else
            key = next_id.to_s
            next_id += 1
          end
          taken << key
        end
        seen[row.id] = true
        [ row.line, key ]
      end
    end

    # "app-<record_no>" IDs come from the CSV export of records entered in the app
    def app_records_for(keys)
      numbers = keys.filter_map { |key| key[/\Aapp-(\d+)\z/, 1]&.to_i }
      @household.records.where(record_no: numbers).index_by { |r| Records::CsvExport.app_key(r) }
    end

    def classify(entry, import_key, versions, app_record = nil)
      record = import_key ? import_key.record : app_record
      if import_key.nil? && app_record.nil?
        entry.merge("kind" => "new")
      elsif record.nil?
        entry.merge("kind" => "deleted")
      elsif record.import_digest == entry["digest"] ||
            (record.import_snapshot.nil? && SheetRow.from_record(record, item: record.title) == entry["values"])
        entry.merge("kind" => "unchanged", "record_id" => record.id)
      else
        versions[record.id.to_s] = record.lock_version
        entry.merge("kind" => "update", "record_id" => record.id, "fields" => field_changes(record, entry["values"]))
      end
    end

    def field_changes(record, sheet)
      app = SheetRow.from_record(record, item: record.import_snapshot&.dig("item") || record.title)
      base = record.import_snapshot || app
      SheetRow::FIELDS.filter_map do |field|
        next if sheet[field] == base[field] && base.key?(field)
        { "field" => field, "base" => base[field], "app" => app[field], "sheet" => sheet[field],
          "conflict" => base.key?(field) && app[field] != base[field] && app[field] != sheet[field] }
      end
    end

    # Item name → category: a saved alias, the category of that name, the suggester's name, or new
    def category_suggestions(rows)
      wanted = rows.select { |r| %w[new deleted].include?(r["kind"]) || r["fields"]&.any? { |f| f["field"] == "item" } }
      aliases = @household.category_aliases.includes(:category).index_by(&:alias)
      categories = @household.categories.to_a
      wanted.group_by { |r| [ r["record_type"], r["values"]["item"] ] }.to_h do |(type, item), list|
        normalized = item.unicode_normalize(:nfkc).strip
        found = aliases[normalized]&.category&.then { |c| c if c.record_type == type } ||
          categories.find { |c| c.record_type == type && c.name_zh == normalized } ||
          categories.find { |c| c.record_type == type && c.name_zh == list.first["suggested_category"] }
        [ "#{type}|#{item}", found ? found.id.to_s : "new:#{list.first['suggested_category']}" ]
      end
    end

    # Saved note keyword → payment method choices (從備註指定付款方式) that match a row the commit may
    # fill: new rows, re-created deleted rows, and updates of records without a payment method.
    # An array, so the priority order survives jsonb.
    def payment_keywords(rows)
      saved = @household.payment_keywords.ordered.includes(:payment_method).to_a
      return [] if saved.empty?
      no_method = @household.records.where(id: rows.filter_map { |r| r["record_id"] if r["kind"] == "update" }, payment_method_id: nil).pluck(:id).to_set
      notes = rows.select { |r| %w[new deleted].include?(r["kind"]) || (r["kind"] == "update" && no_method.include?(r["record_id"])) }
        .filter_map { |r| r["values"]["payment_note"].presence }
      saved.select { |k| notes.any? { |note| PaymentKeyword.match?(k.keyword, note) } }.map do |k|
        method = k.payment_method if k.payment_method&.archived_at.nil?
        { "keyword" => k.keyword, "choice" => method ? "pm:#{method.id}" : PaymentMethods::FromNotes::SKIP }
      end
    end

    # Maintenance chains by (category, room); only the latest row keeps its next-due date (PRD §9)
    def chains(result, rows)
      by_line = rows.index_by { |r| r["line"] }
      result.chains.map do |chain|
        latest = chain.latest
        due = latest&.next_due_on
        action = due.nil? || (@today - due).to_i <= STALE_CHAIN_DAYS ? "keep" : "clear"
        { "category" => chain.category, "details_key" => chain.details_key, "lines" => chain.rows.map(&:line),
          "latest_line" => latest&.line, "next_due_on" => due&.iso8601, "action" => action,
          "keys" => chain.rows.map { |r| by_line[r.line]["key"] } }
      end
    end
  end
end
