# Photos attached before duplicate checking get their "looks like" fingerprint (Photos::Fingerprint),
# so picking one of them again is caught too. A photo whose file can't be read is left without one.
class BackfillPhotoFingerprints < ActiveRecord::Migration[8.1]
  def up
    ActiveStorage::Attachment.where(record_type: "Record", name: "photos").includes(:blob).find_each do |attachment|
      blob = attachment.blob
      next if blob.metadata["fingerprint"]

      fingerprint = blob.open { |file| Photos::Fingerprint.call(file.path) }
      blob.update_columns(metadata: blob.metadata.merge("fingerprint" => fingerprint)) if fingerprint
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
      next
    end
  end

  def down; end
end
