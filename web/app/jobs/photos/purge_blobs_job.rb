module Photos
  # Deletes files (and their variants) whose records were removed without callbacks, e.g. by
  # Households::Purge (PRD §15)
  class PurgeBlobsJob < ApplicationJob
    queue_as :default

    def perform(blob_ids)
      ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge)
    end
  end
end
