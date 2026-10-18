class Session < ApplicationRecord
  LIFETIME = 1.year
  # Sliding expiry is written at most this often, not on every request
  REFRESH_AFTER = 1.day

  belongs_to :user

  before_validation(on: :create) { self.last_seen_at = Time.current; self.expires_at = LIFETIME.from_now }

  scope :active, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  REAUTH_WINDOW = 10.minutes

  def refresh_due? = last_seen_at < REFRESH_AFTER.ago

  def recently_reauthenticated? = reauthenticated_at.present? && reauthenticated_at > REAUTH_WINDOW.ago

  def refresh!
    update!(last_seen_at: Time.current, expires_at: LIFETIME.from_now)
  end
end
