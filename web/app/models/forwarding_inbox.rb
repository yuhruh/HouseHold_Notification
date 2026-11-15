# A ledger's forwarding address for utility emails (台電 and 台水 share it): whoever receives the
# company's emails has Gmail forward them to `address`, the app's own mailbox plus this ledger's
# token, and the app reads them from there (Utilities::ForwardedMail). Created when Electricity or
# Water is turned on, and removed when the last of them is disconnected.
#
# Members may always forward here; `allowed_senders` are the other emails the owner added. Gmail's
# request to confirm forwarding is kept until it's used, and `setup_emails_sent` says when each
# forwarder was last sent the setup email.
class ForwardingInbox < ApplicationRecord
  EMAIL = URI::MailTo::EMAIL_REGEXP
  SETUP_RESEND_AFTER = 1.minute
  CONFIRMATION_KEPT = 7.days

  # Someone who may forward here: a member (role "owner", "co_owner" or "viewer") or an email the
  # owner added ("added"), and when they were last sent the setup email
  Forwarder = Data.define(:email, :role, :setup_sent_at) do
    def added? = role == "added"
  end

  belongs_to :household

  normalizes :allowed_senders, with: ->(emails) { Array(emails).map { it.to_s.strip.downcase }.compact_blank.uniq }

  validates :inbox_token, presence: true, uniqueness: true
  validates :household_id, uniqueness: true
  validate :allowed_senders_are_emails

  before_validation(on: :create) { self.inbox_token ||= self.class.new_token }

  def self.new_token = SecureRandom.alphanumeric(10, chars: [ *"a".."z", *"0".."9" ])

  # The app's Gmail sender (Rails credentials gmail.sender), or nil where none is set up
  def self.mailbox = Rails.application.credentials.dig(:gmail, :sender).presence

  # "household.bills+h1-7f3k2m9q0a@gmail.com": Gmail delivers it to the app's mailbox, and the part
  # after "+" says which ledger it's for
  def address
    return unless inbox_token && (mailbox = self.class.mailbox)

    local, domain = mailbox.split("@", 2)
    "#{local}+h#{household_id}-#{inbox_token}@#{domain}"
  end

  # The ledger's accounts whose bills come by email, Electricity first
  def mail_accounts = [ household.electricity_account, household.water_account ].compact

  # Members first (owner, co-owners, viewers), then the emails the owner added
  def forwarders
    members = household.memberships.includes(:user).sort_by { Membership.roles.keys.index(it.role) }
      .filter_map { |m| [ m.user.email_address.to_s.downcase, m.role ] if m.user.email_address.present? }
    (members + allowed_senders.map { [ it, "added" ] }).uniq(&:first)
      .map { |email, role| Forwarder.new(email:, role:, setup_sent_at: setup_sent_at(email)) }
  end

  def forwarder?(email) = forwarders.any? { it.email == email.to_s.downcase }

  def setup_sent_at(email) = setup_emails_sent[email.to_s.downcase]&.then { Time.zone.parse(it) }

  def setup_sent_recently?(email) = setup_sent_at(email)&.after?(SETUP_RESEND_AFTER.ago) || false

  def setup_sent!(email)
    update!(setup_emails_sent: setup_emails_sent.merge(email.to_s.downcase => Time.current.iso8601))
  end

  # Gmail's request to confirm forwarding (a link, or a code from older Gmail), while it's still
  # useful: under 7 days old and no company email forwarded by a filter since
  def pending_confirmation?
    (forwarding_link.present? || forwarding_code.present?) && forwarding_code_at&.after?(CONFIRMATION_KEPT.ago) &&
      mail_accounts.none? { it.last_success_at && it.last_success_at > forwarding_code_at }
  end

  # Forwarding was confirmed in Gmail: a filter has forwarded a company email here
  def confirmed? = mail_accounts.any?(&:last_success_at)

  private

  def allowed_senders_are_emails
    bad = allowed_senders.grep_v(EMAIL)
    errors.add(:allowed_senders, :invalid, emails: bad.join(", ")) if bad.any?
  end
end
