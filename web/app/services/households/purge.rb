module Households
  # Deletes a household and everything in it, in an explicit order, in one transaction (PRD §15).
  # Tables added by later milestones (records, photos, reminders…) get their own step here.
  class Purge
    def self.call(household, actor:)
      # Photo files go after the commit; their attachment rows go with the records
      photo_blob_ids = ActiveStorage::Attachment.where(record_type: "Record", record_id: household.records.select(:id)).pluck(:blob_id)
      household.with_lock do
        ActiveStorage::Attachment.where(record_type: "Record", record_id: household.records.select(:id)).delete_all
        # Model-level deletes: delete_all on these associations would nullify (no dependent option)
        ImportBatchChange.where(import_batch_id: ImportBatch.where(household:).select(:id)).delete_all
        [ Notification, ReminderDelivery, NotificationPreference, RecordEvent, ImportKey, ImportPreview, Record, RecurringTemplate, ImportBatch, CategoryAlias, BillerCode, Category, PaymentKeyword, PaymentMethod ].each { |model| model.where(household:).delete_all }
        household.invitations.delete_all
        household.memberships.delete_all
        User.where(last_household_id: household.id).update_all(last_household_id: nil)
        SecurityEvent.record!("household_deleted", actor:, household:)
        household.delete
      end
      Photos::PurgeBlobsJob.perform_later(photo_blob_ids) if photo_blob_ids.any?
    end
  end
end
