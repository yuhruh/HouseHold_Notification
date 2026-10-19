# A parsed upload waiting for "Continue" (PRD §9): the planned rows, the user's choices and the
# lock_version of every record it would update, so a commit after concurrent edits is refused.
class ImportPreview < ApplicationRecord
  TTL = 1.day

  belongs_to :household
  belongs_to :user, optional: true

  scope :pending, -> { where(committed_at: nil).where(expires_at: Time.current..) }

  def rows_of(kind) = rows.select { |row| row["kind"] == kind }
end
