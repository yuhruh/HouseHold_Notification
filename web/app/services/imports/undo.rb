module Imports
  # Undo the latest import batch, all or nothing (PRD §9): created records are deleted (their sheet
  # IDs freed, or retired again for re-created ones) and updated records get their old values back.
  class Undo
    def self.call(batch, user:)
      raise ArgumentError, "only the latest import can be undone" unless batch.undoable?

      ImportBatch.transaction do
        batch.changes_made.order(id: :desc).each do |change|
          record = batch.household.records.find_by(id: change.record_id)
          next unless record

          if change.created?
            keys = batch.household.import_keys.where(record_id: record.id)
            keys.where(import_batch_id: batch.id).delete_all
            keys.update_all(record_id: nil, status: "retired", retired_digest: record.import_digest)
            RecordEvent.log!(record, :import_undone, user:)
            record.destroy!
          else
            record.assign_attributes(change.before)
            record.save!
            RecordEvent.create!(household: batch.household, record_id: record.id, user:, import_batch_id: batch.id,
              action: "import_undone", diff: record.saved_changes.except(*RecordEvent::IGNORED))
          end
        end
        batch.update!(undone_at: Time.current)
      end
    end
  end
end
