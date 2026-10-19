# One committed sheet import (PRD §9). Only the latest batch can be undone, all or nothing.
class ImportBatch < ApplicationRecord
  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  has_many :changes_made, class_name: "ImportBatchChange", dependent: :delete_all
  has_many :records, dependent: :nullify

  scope :active, -> { where(undone_at: nil) }

  def undoable? = undone_at.nil? && household.import_batches.active.order(:id).last == self

  # Undo is refused once any of its records was edited, marked paid, deleted or given photos (PRD M5)
  def undo_blocked?
    ids = changes_made.pluck(:record_id)
    household.records.where(id: ids).count < ids.uniq.size ||
      ActiveStorage::Attachment.where(record_type: "Record", record_id: ids, name: "photos").where(created_at: created_at..).exists? ||
      RecordEvent.where(household_id:, record_id: ids, action: %w[updated marked_paid deleted]).where(created_at: created_at..).exists?
  end
end
