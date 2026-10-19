module SheetImport
  # Plain-text report for `bin/rails import:dry_run`. Feeds the Sheet cleanup log in docs/TRACKING.md.
  class DryRunReport
    def initialize(result, today: Date.current)
      @result = result
      @today = today
    end

    def to_s
      out = []
      r = @result
      out << "== Sheet import dry run: parser + Record validations (nothing was written) =="
      if r.file_errors.any?
        out.push("", "FILE ERRORS (fix these first):")
        r.file_errors.each { |e| out << "  - #{e}" }
        return out.join("\n")
      end

      out << "Rows: #{r.rows.size} · rows with errors: #{r.error_rows.size} · rows with warnings: #{r.warning_rows.size}"
      out << "Result: #{r.ok? ? 'READY (0 errors)' : 'NOT READY'}"

      section(out, "ERRORS by type", r.error_rows.flat_map { |row| row.errors.map { |e| [ generalize(e), row ] } })
      section(out, "WARNINGS by type", r.warning_rows.flat_map { |row| row.warnings.map { |w| [ generalize(w), row ] } })

      if r.id_reassignments.any?
        out.push("", "IDs TO PASTE BACK (repeated IDs get a new one):")
        r.id_reassignments.each { |a| out << "  line #{a[:line]}: ID #{a[:old_id]} → #{a[:new_id]}" }
      end

      out.push("", "CATEGORY MAPPING (item → suggested category):")
      r.rows.select(&:category).group_by { |row| [ row.item, row.category.name ] }.sort_by { |(_, c), _| c }.each do |(item, category), rows|
        out << format("  %-24s → %-14s %3d rows", item, category, rows.size)
      end

      out.push("", "MAINTENANCE CHAINS (category · room):")
      r.chains.each do |chain|
        due = chain.next_due_on
        state = if due.nil? then "no next-due"
        elsif due >= @today then "due #{due} (in #{(due - @today).to_i} d) → Keep"
        elsif (@today - due).to_i > Parser::STALE_CHAIN_DAYS then "passed #{due} (#{(@today - due).to_i} d ago) → Clear"
        else "passed #{due} (#{(@today - due).to_i} d ago) → Keep"
        end
        out << "  #{chain.category} · #{chain.details_key.presence || '(no room)'} · #{chain.rows.size} rows · #{state}"
      end

      out.push("", "TOTALS of rows without errors:")
      clean = r.rows.reject { |row| row.errors.any? }
      clean.group_by(&:currency).each do |currency, rows|
        out << "  #{currency}: Required #{sum(rows, :required)} · Paid #{sum(rows, :paid)}"
      end
      if r.sheet_total
        paid = clean.sum { |row| row.paid || 0 }
        out << if paid == r.sheet_total
          "  Sheet Total #{format_amount(r.sheet_total)} = Paid ✓"
        else
          "  Sheet Total #{format_amount(r.sheet_total)} ≠ Paid #{format_amount(paid)} (difference #{format_amount(r.sheet_total - paid)})"
        end
      end
      out.join("\n")
    end

    private

    def section(out, title, pairs)
      return if pairs.empty?
      out.push("", "#{title}:")
      pairs.group_by(&:first).sort_by { |_, v| -v.size }.each do |message, items|
        lines = items.map { |_, row| row.line }.uniq
        out << "  [#{items.size}] #{message}"
        out << "      lines: #{lines.first(30).join(', ')}#{' …' if lines.size > 30}"
      end
    end

    # Group messages by shape: strip quoted values and numbers.
    def generalize(message) = message.gsub(/"[^"]*"/, '"…"').gsub(/\d[\d,.\-\/]*/, "N")

    def sum(rows, field) = format_amount(rows.sum { |row| row[field] || 0 })
    def format_amount(amount) = amount.to_d.to_s("F").delete_suffix(".0")
  end
end
