class User < ApplicationRecord
  DEFAULT_TIME_ZONE = "Asia/Taipei".freeze
  UNCONFIRMED_TTL = 7.days

  # Google-only users have no password, so presence isn't validated
  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy

  normalizes :email_address, :unconfirmed_email, with: ->(e) { e.strip.downcase }

  validates :password, length: { in: 8..72 }, confirmation: true, allow_nil: true
  validates :time_zone, inclusion: { in: ->(_) { TZInfo::Timezone.all_identifiers } }
  validates :locale, inclusion: { in: ->(_) { I18n.available_locales.map(&:to_s) } }, allow_nil: true

  # The token embeds the pending address, so changing it invalidates older links
  generates_token_for :email_confirmation, expires_in: 24.hours do
    unconfirmed_email
  end

  scope :stale_unconfirmed, -> { where(email_address: nil, created_at: ...UNCONFIRMED_TTL.ago).where.missing(:identities) }

  def self.valid_time_zone(name)
    TZInfo::Timezone.all_identifiers.include?(name) ? name : DEFAULT_TIME_ZONE
  end

  # Moves the pending address into email_address. False if someone verified it first.
  def confirm_email!
    update!(email_address: unconfirmed_email, unconfirmed_email: nil, email_confirmed_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    reload
    false
  end

  def password_set? = password_digest.present?
end
