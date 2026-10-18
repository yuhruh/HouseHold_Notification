# Server-side state for one "Continue with Google" round trip (PRD §10): time zone and return path.
class AuthHandoff < ApplicationRecord
  TTL = 10.minutes

  belongs_to :user, optional: true

  before_validation(on: :create) do
    self.requested_at = Time.current
    self.expires_at = TTL.from_now
  end

  scope :expired, -> { where(expires_at: ...Time.current) }

  # Returns the handoff once, if it is still valid.
  def self.consume(id)
    return if id.blank?

    transaction do
      handoff = lock.find_by(id:, used_at: nil, expires_at: Time.current..)
      handoff&.update!(used_at: Time.current)
      handoff
    end
  end

  # Only same-site paths, never "//host" or a full URL
  def self.safe_return_to(path)
    path if path.is_a?(String) && path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
  end
end
