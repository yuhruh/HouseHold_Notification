module Imports
  # "Continue" on the preview (PRD §9): every write in ONE transaction. Any failure rolls back
  # everything and raises Aborted naming the row, sheet ID and messages.
  class Commit
    class Aborted < StandardError
      attr_reader :line, :key, :messages

      def initialize(message, line: nil, key: nil, messages: [])
        super(message)
        @line, @key, @messages = line, key, messages
      end
    end

    TRACKED = Record.column_names - %w[id household_id created_at updated_at lock_version settled record_no]

    def self.call(...) = new(...).call

    def initialize(preview, user:)
      @preview, @user = preview, user
      @household = preview.household
      @choices = preview.choices
      @now = Time.current
    end

    def call
      raise Aborted, "expired" if @preview.committed_at || @preview.expires_at.past?

      ImportBatch.transaction do
        check_versions!
        @batch = @household.import_batches.create!(created_by: @user, filename: @preview.filename, row_count: @preview.rows.size)
        @categories = resolve_categories
        save_aliases
        @payment_keywords = resolve_payment_keywords
        @next_due = chain_next_due
        counts = Hash.new(0)
        @preview.rows.each do |row|
          case row["kind"]
          when "new" then create(row) && counts[:created] += 1
          when "update" then update(row) && counts[:updated] += 1
          when "unchanged" then counts[:unchanged] += 1
          when "deleted"
            if @choices.dig("deleted", row["line"].to_s) == "recreate" then create(row) && counts[:created] += 1
            else counts[:skipped] += 1
            end
          end
        end
        @batch.update!(created_count: counts[:created], updated_count: counts[:updated],
          unchanged_count: counts[:unchanged], skipped_count: counts[:skipped])
        @preview.update!(committed_at: @now)
        @batch
      end
    end

    private

    # Records changed in the app since the preview was made → refuse (lock_version)
    def check_versions!
      versions = @preview.record_versions
      current = @household.records.where(id: versions.keys).pluck(:id, :lock_version).to_h { |id, v| [ id.to_s, v ] }
      changed = versions.reject { |id, version| current[id] == version }
      raise Aborted.new("stale", messages: changed.keys) if changed.any?
    end

    def resolve_categories
      @choices.fetch("categories", {}).to_h do |mapping, choice|
        type, = mapping.split("|", 2)
        category = if choice.start_with?("new:")
          name = choice.delete_prefix("new:").strip
          @household.categories.find_or_create_by!(record_type: type, name_zh: name) do |c|
            suggestion = SheetImport::CategorySuggester.suggest(name, type.to_sym)
            c.assign_attributes(detail_required: suggestion.detail_required && suggestion.name == name,
              detail_label_zh: (suggestion.detail_label if suggestion.name == name), position: 100)
          end
        else
          @household.categories.find(choice)
        end
        raise Aborted.new("category_type", messages: [ mapping ]) unless category.record_type == type
        [ mapping, category ]
      end
    end

    # Saved item-name mappings are reused by later imports (PRD → Import mapping)
    def save_aliases
      @categories.each do |mapping, category|
        item = mapping.split("|", 2).last.unicode_normalize(:nfkc).strip
        next if item == category.name_zh
        @household.category_aliases.find_or_initialize_by(alias: item).update!(category:)
      end
    end

    # [[keyword, payment method or nil]] in priority order; a changed choice is saved for next time
    def resolve_payment_keywords
      methods = @household.payment_methods.active.index_by { |pm| "pm:#{pm.id}" }
      Array(@choices["payment_keywords"]).map do |entry|
        method = methods[entry["choice"]]
        @household.payment_keywords.find_by(keyword: entry["keyword"])&.update!(payment_method: method)
        [ entry["keyword"], method ]
      end
    end

    # A record without a payment method gets the first matching keyword's (never overwrites one)
    def fill_payment_method(record)
      return if record.payment_method_id || record.payment_note.blank?
      _, method = @payment_keywords.find { |keyword, pm| pm && PaymentKeyword.match?(keyword, record.payment_note) }
      record.payment_method = method if method
    end

    # Only the chain's latest row keeps a next-due date: Keep, Clear or a new date (PRD §9)
    def chain_next_due
      @choices.fetch("chains", []).each_with_object({}) do |chain, due|
        chain["keys"].each { |key| due[key] = nil }
        latest_key = chain["keys"][chain["lines"].index(chain["latest_line"])] if chain["latest_line"]
        next unless latest_key
        due[latest_key] = case chain["action"]
        when "keep" then chain["next_due_on"]
        when "new_date" then chain["new_date"].presence
        end
      end
    end

    def create(row)
      values = row["values"]
      category = category_for(row)
      record = @household.records.new(SheetRow.record_attributes(values).merge(
        "record_type" => row["record_type"], "category" => category, "title" => category.name_zh,
        "import_key" => row["key"], "import_digest" => row["digest"], "import_snapshot" => values,
        "imported_at" => @now, "import_batch" => @batch, "created_by" => @user
      ))
      record.next_due_on = @next_due[row["key"]] if @next_due.key?(row["key"])
      fill_payment_method(record)
      save!(record, row)

      key = @household.import_keys.find_by(key: row["key"])
      if key
        key.update!(record:, status: "active")
      else
        @household.import_keys.create!(key: row["key"], record:, import_batch: @batch,
          source_key: (row["sheet_key"] if row["sheet_key"] != row["key"]))
      end
      @batch.changes_made.create!(record_id: record.id, action: "created", after: record.attributes.slice(*TRACKED))
      RecordEvent.create!(household: @household, record_id: record.id, user: @user, import_batch_id: @batch.id,
        action: "import_created", diff: values)
    end

    def update(row)
      record = @household.records.lock.find(row["record_id"])
      before = record.attributes.slice(*TRACKED)
      row["fields"].each do |change|
        next if change["conflict"] && @choices.dig("conflicts", "#{row['line']}-#{change['field']}") == "app"
        if change["field"] == "item"
          record.category = category_for(row)
          record.title = record.category.name_zh
        else
          record[change["field"]] = change["sheet"]
        end
      end
      record.next_due_on = @next_due[row["key"]] if @next_due.key?(row["key"])
      record.assign_attributes(import_digest: row["digest"], import_snapshot: row["values"], imported_at: @now, import_batch: @batch)
      record.import_key ||= row["key"] # an app-entered record linked by its exported app- ID
      fill_payment_method(record)
      save!(record, row)
      @household.import_keys.create_with(record:, import_batch: @batch).find_or_create_by!(key: row["key"])
      @batch.changes_made.create!(record_id: record.id, action: "updated", before:, after: record.attributes.slice(*TRACKED))
      RecordEvent.create!(household: @household, record_id: record.id, user: @user, import_batch_id: @batch.id,
        action: "import_updated", diff: record.saved_changes.except(*RecordEvent::IGNORED, "import_snapshot", "imported_at", "import_digest", "import_batch_id"))
    end

    def category_for(row)
      @categories.fetch("#{row['record_type']}|#{row['values']['item']}") do
        raise Aborted.new("category_missing", line: row["line"], key: row["key"], messages: [ row["values"]["item"] ])
      end
    end

    def save!(record, row)
      record.save!(context: :import)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      messages = record.errors.any? ? record.errors.full_messages : [ e.message.lines.first.strip ]
      raise Aborted.new("row", line: row["line"], key: row["key"], messages:)
    end
  end
end
