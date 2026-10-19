module Records
  # Owner's "delete all records" (Settings → Danger zone): every record of one household with its
  # photos, history, reminders and import bookkeeping, so the sheet can be imported again from
  # scratch (rows come back as new, not as "deleted in the app"). The household, members,
  # categories, aliases and payment methods stay.
  #
  # Recurring bills either go too, or stay with their start moved to this month: generation catches
  # up every period from the start that has no record, so keeping the old start would recreate
  # every past bill on the next nightly run.
  class PurgeAll
    def self.call(household, actor:, delete_templates:, today: Date.current)
      record_ids = household.records.select(:id)
      photo_blob_ids = ActiveStorage::Attachment.where(record_type: "Record", record_id: record_ids).pluck(:blob_id)
      count = household.records.count
      household.with_lock do
        ActiveStorage::Attachment.where(record_type: "Record", record_id: record_ids).delete_all
        ImportBatchChange.where(import_batch_id: ImportBatch.where(household:).select(:id)).delete_all
        # reminder_logs and reminder_snoozes go with their records (on_delete: cascade)
        [ Notification, ReminderDelivery, RecordEvent, ImportKey, ImportPreview, Record, ImportBatch ].each { |model| model.where(household:).delete_all }
        if delete_templates
          RecurringTemplate.where(household:).delete_all
        else
          RecurringTemplate.where(household:, starts_on: ...today.beginning_of_month).update_all(starts_on: today.beginning_of_month)
        end
        SecurityEvent.record!("records_deleted", actor:, household:, count:, templates_deleted: delete_templates)
      end
      Photos::PurgeBlobsJob.perform_later(photo_blob_ids) if photo_blob_ids.any?
      count
    end
  end
end
