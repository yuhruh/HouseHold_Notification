# Audit trail for account and household changes (PRD data model). Keeps ids only, no personal data.
class SecurityEvent < ApplicationRecord
  KINDS = %w[email_change_requested password_changed google_connected google_disconnected sessions_revoked
             household_updated member_joined role_changed member_removed member_left ownership_transferred household_deleted
             account_deleted records_deleted].freeze

  validates :kind, inclusion: { in: KINDS }

  def self.record!(kind, user: nil, actor: nil, household: nil, **metadata)
    create!(kind:, user_id: user&.id, actor_id: actor&.id, household_id: household&.id, metadata:)
  end

  def actor = actor_id && User.find_by(id: actor_id)
end
