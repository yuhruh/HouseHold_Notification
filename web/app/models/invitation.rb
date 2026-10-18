# Invite by email (PRD §12, §12a). The token in the link only routes; accepting needs a pending
# invitation and the signed-in user's verified email_address equal to the invited email.
class Invitation < ApplicationRecord
  EXPIRY_CHOICES = %w[7 30 custom never].freeze

  belongs_to :household
  belongs_to :invited_by, class_name: "User", optional: true

  enum :role, { co_owner: "co_owner", viewer: "viewer" }, validate: true
  normalizes :email, with: ->(e) { e.strip.downcase }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :open, -> { where(accepted_at: nil, declined_at: nil, revoked_at: nil) }
  scope :unexpired, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }
  scope :pending, -> { open.unexpired }

  attr_reader :token

  def self.pending_for(user)
    user.email_address ? pending.where(email: user.email_address) : none
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_by_token(token) = find_by(token_digest: digest(token))

  # A new invitation for the same address revokes any open one, expired or not
  def self.issue!(household:, invited_by:, email:, role:, expires_at:)
    token = SecureRandom.urlsafe_base64(32)
    transaction do
      household.invitations.open.where(email: email.to_s.strip.downcase).update_all(revoked_at: Time.current)
      household.invitations.create!(invited_by:, email:, role:, expires_at:, token_digest: digest(token))
        .tap { |invitation| invitation.instance_variable_set(:@token, token) }
    end
  end

  # "7" / "30" days, a custom date (end of that day in the inviter's zone) or never
  def self.expiry_from(choice, custom_date = nil)
    case choice.to_s
    when "never" then nil
    when "custom" then Date.parse(custom_date.to_s).in_time_zone.end_of_day
    when "30" then 30.days.from_now
    else 7.days.from_now
    end
  rescue Date::Error
    7.days.from_now
  end

  def pending? = accepted_at.nil? && declined_at.nil? && revoked_at.nil? && (expires_at.nil? || expires_at.future?)

  def acceptable_by?(user) = pending? && user.email_address.present? && user.email_address == email

  def accept!(user)
    raise ActiveRecord::RecordNotFound unless acceptable_by?(user)

    transaction do
      lock!
      raise ActiveRecord::RecordNotFound unless acceptable_by?(user)

      household.memberships.find_or_create_by!(user:) { |membership| membership.role = role }
      update!(accepted_at: Time.current)
    end
  end

  def decline!(user)
    raise ActiveRecord::RecordNotFound unless acceptable_by?(user)

    update!(declined_at: Time.current)
  end

  def revoke! = update!(revoked_at: Time.current)

  # "m***@gmail.com", for the wrong-account message
  def masked_email
    local, domain = email.split("@", 2)
    "#{local[0]}***@#{domain}"
  end
end
