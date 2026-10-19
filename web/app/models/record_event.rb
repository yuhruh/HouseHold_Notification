# One line of a record's activity log (PRD → Data model). Kept after the record is deleted,
# with a full snapshot, so a deletion can be traced and re-entered by hand.
class RecordEvent < ApplicationRecord
  IGNORED = %w[id household_id created_at updated_at lock_version settled record_no].freeze

  belongs_to :household
  belongs_to :user, optional: true

  enum :action, %w[created updated deleted marked_paid import_created import_updated import_undone].index_by(&:itself), validate: true

  # created/deleted keep a full snapshot; updates keep [before, after] per changed field
  def self.log!(record, action, user:)
    diff = case action.to_s
    when "created", "deleted", "import_undone" then record.attributes.except(*IGNORED)
    else record.saved_changes.except(*IGNORED)
    end
    create!(household_id: record.household_id, record_id: record.id, user:, action:, diff:)
  end
end
