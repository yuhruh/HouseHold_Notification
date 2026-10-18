# Emailed re-authentication code (PRD §15). Stored as an HMAC, valid 10 minutes, single use, dead
# after 5 wrong attempts.
class ReauthCode < ApplicationRecord
  TTL = 10.minutes
  MAX_ATTEMPTS = 5
  PURPOSES = %w[delete_account change_email disconnect_google transfer_ownership delete_household].freeze

  belongs_to :user

  validates :purpose, inclusion: { in: PURPOSES }

  scope :usable, -> { where(used_at: nil, expires_at: Time.current..).where(attempts: ...MAX_ATTEMPTS) }

  def self.digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code.to_s)

  # Returns [record, plain code]; older codes for the user stop working
  def self.issue!(user, purpose)
    code = format("%06d", SecureRandom.random_number(1_000_000))
    transaction do
      user.reauth_codes.usable.update_all(used_at: Time.current)
      [ user.reauth_codes.create!(purpose:, code_digest: digest(code), expires_at: TTL.from_now), code ]
    end
  end

  # True once for the right code; every wrong guess counts against the latest code
  def self.verify(user, code)
    record = user.reauth_codes.usable.order(:created_at).last
    return false unless record

    record.with_lock do
      return false unless record.used_at.nil? && record.attempts < MAX_ATTEMPTS && record.expires_at.future?

      if ActiveSupport::SecurityUtils.secure_compare(record.code_digest, digest(code.to_s.strip))
        record.update!(used_at: Time.current)
        true
      else
        record.increment!(:attempts)
        false
      end
    end
  end
end
