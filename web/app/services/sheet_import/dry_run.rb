module SheetImport
  # Dry-run #2 (PRD → M2 first PR): saves every row the parser accepted as a Record, with the
  # :import validations and the database constraints, in a scratch household, then rolls it all
  # back. Record errors are added to the rows, so the report and `ok?` include them.
  class DryRun
    def self.call(result) = new(result).call

    def initialize(result)
      @result = result
      @new_ids = result.id_reassignments.to_h { |a| [ a[:line], a[:new_id] ] }
    end

    def call
      return @result if @result.file_errors.any?

      # The report is in English
      I18n.with_locale(:en) { check_all }
      @result
    end

    private

    def check_all
      ActiveRecord::Base.transaction do
        household = Household.create!(name: "Import dry run")
        Categories::Seed.call(household)
        @result.rows.each { |row| check(household, row) if row.errors.empty? }
        raise ActiveRecord::Rollback
      end
    end

    def check(household, row)
      record = build(household, row)
      ActiveRecord::Base.transaction(requires_new: true) do
        next if record.save(context: :import)
        record.errors.full_messages.each { |message| row.error("Record: #{message}") }
        raise ActiveRecord::Rollback
      end
    rescue ActiveRecord::ActiveRecordError => e
      row.error("Record: #{e.class.name.demodulize} (#{e.message.lines.first.strip})")
    end

    def build(household, row)
      category = category_for(household, row)
      household.records.new(
        record_type: row.record_type.to_s, category:, title: category.name_zh, details: row.details,
        period: row.period, currency: row.currency, amount_required: row.required, amount_paid: row.paid,
        paid_on: row.finished_on, payment_note: row.note, next_due_on: row.next_due_on,
        import_key: @new_ids.fetch(row.line, row.id), imported_at: Time.current
      )
    end

    # The suggested category within the row's own type; created when it isn't a seeded one,
    # as the preview's "new category" would.
    def category_for(household, row)
      suggestion = row.category
      household.categories.find_or_create_by!(record_type: row.record_type.to_s, name_zh: suggestion.name) do |category|
        category.assign_attributes(detail_required: suggestion.detail_required, detail_label_zh: suggestion.detail_label, position: 100)
      end
    end
  end
end
