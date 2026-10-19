module Households
  # Deletes a household and everything in it, in an explicit order, in one transaction (PRD §15).
  # Tables added by later milestones (records, photos, reminders…) get their own step here.
  class Purge
    def self.call(household, actor:)
      household.with_lock do
        # Model-level deletes: delete_all on these associations would nullify (no dependent option)
        ImportBatchChange.where(import_batch_id: ImportBatch.where(household:).select(:id)).delete_all
        [ RecordEvent, ImportKey, ImportPreview, Record, RecurringTemplate, ImportBatch, CategoryAlias, Category, PaymentMethod ].each { |model| model.where(household:).delete_all }
        household.invitations.delete_all
        household.memberships.delete_all
        User.where(last_household_id: household.id).update_all(last_household_id: nil)
        SecurityEvent.record!("household_deleted", actor:, household:)
        household.delete
      end
    end
  end
end
