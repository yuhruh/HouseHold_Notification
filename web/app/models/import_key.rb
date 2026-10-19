# A sheet ID ever used in the household. Retired when its record is deleted in the app.
class ImportKey < ApplicationRecord
  belongs_to :household
  belongs_to :record, optional: true
  belongs_to :import_batch, optional: true

  enum :status, { active: "active", retired: "retired" }, validate: true
end
