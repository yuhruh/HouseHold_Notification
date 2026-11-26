class User < ApplicationRecord
  DEFAULT_TIME_ZONE = "Asia/Taipei".freeze
  UNCONFIRMED_TTL = 7.days
  EMAIL_MAX = 254
  DISPLAY_NAME_MAX = 60

  # Google-only users have no password, so presence isn't validated
  has_secure_password validations: false
  has_one_attached :avatar
  has_many :sessions, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :households, through: :memberships
  has_many :reauth_codes, dependent: :delete_all
  has_many :notification_preferences, dependent: :delete_all
  has_many :reminder_deliveries, dependent: :destroy
  has_many :notifications, dependent: :delete_all
  has_many :push_subscriptions, dependent: :delete_all
  has_many :supply_favorites, dependent: :delete_all
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :invited_by_id, inverse_of: :invited_by, dependent: :nullify
  belongs_to :last_household, class_name: "Household", optional: true

  normalizes :email_address, :unconfirmed_email, with: ->(e) { e.strip.downcase }
  # One line of plain text: other members see it, and it's written into emails the app sends
  normalizes :display_name, with: ->(name) { name.gsub(/[[:cntrl:]]/, " ").squish }

  # Each is checked when it changes, so an account from before these rules can still be saved.
  # An address is exactly one address: mail goes to it as written, and "a@x.com, b@y.com" would
  # reach everyone on the list.
  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: EMAIL_MAX },
    allow_nil: true, if: :will_save_change_to_email_address?
  validates :unconfirmed_email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: EMAIL_MAX },
    allow_nil: true, if: :will_save_change_to_unconfirmed_email?
  validates :display_name, length: { maximum: DISPLAY_NAME_MAX }, if: :will_save_change_to_display_name?
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

  # A Google-only user has no digest, so Rails' check would answer at once. Hash the attempt anyway,
  # as authenticate_by does for an unknown address, so sign-in timing doesn't tell which addresses
  # belong to Google-only accounts (PRD §10).
  def authenticate_password(unencrypted_password)
    return super if password_set?

    self.class.new(password: unencrypted_password)
    false
  end

  def google_identity = identities.find_by(provider: "google_oauth2")

  # Sign-in methods left if Google were disconnected (PRD §10: never remove the last one)
  def can_disconnect_google? = password_set? && email_address.present?

  # GET / lands here: last household if still a member, else the first one (PRD §12a)
  def home_household
    (last_household if last_household_id && memberships.exists?(household_id: last_household_id)) ||
      households.order("memberships.created_at").first
  end
end
