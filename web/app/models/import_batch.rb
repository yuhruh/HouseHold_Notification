# One committed sheet import (PRD §9). Only the latest batch can be undone, all or nothing.
class ImportBatch < ApplicationRecord
  belongs_to :household
  belongs_to :created_by, class_name: "User", optional: true
  has_many :changes_made, class_name: "ImportBatchChange", dependent: :delete_all
  has_many :records, dependent: :nullify

  scope :active, -> { where(undone_at: nil) }

  def undoable? = undone_at.nil? && household.import_batches.active.order(:id).last == self
end
