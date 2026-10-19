class ImportBatchChange < ApplicationRecord
  belongs_to :import_batch

  enum :action, { created: "created", updated: "updated" }, validate: true
end
