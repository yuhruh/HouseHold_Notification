# A ledger's 台電 bills (Ledger settings › Electricity). Whoever receives 台電's emails has Gmail
# forward them to `inbox_address`, the app's own mailbox plus this ledger's token; the app reads
# them from there. The 11-digit 電號 is optional: the first accepted bill email sets it, and emails
# for any other 電號 are then ignored. `allowed_senders` are extra emails (besides the members')
# that may forward to it.
class ElectricityAccount < UtilityAccount
  EMAIL = URI::MailTo::EMAIL_REGEXP
  BILLED_EVERY = 2.months
  MISSING_AFTER = 7.days

  normalizes :allowed_senders, with: ->(emails) { Array(emails).map { it.to_s.strip.downcase }.compact_blank.uniq }

  validates :customer_code, format: { with: /\A\d{11}\z/ }, uniqueness: true, allow_nil: true
  validate :allowed_senders_are_emails

  before_create { self.inbox_token ||= self.class.new_token }

  def self.new_token = SecureRandom.alphanumeric(10, chars: [ *"a".."z", *"0".."9" ])

  # The app's Gmail sender (Rails credentials gmail.sender), or nil where none is set up
  def self.mailbox = Rails.application.credentials.dig(:gmail, :sender).presence

  # "household.bills+h1-7f3k2m9q0a@gmail.com": Gmail delivers it to the app's mailbox, and the
  # part after "+" says which ledger it's for
  def inbox_address
    return unless inbox_token && (mailbox = self.class.mailbox)

    local, domain = mailbox.split("@", 2)
    "#{local}+h#{household_id}-#{inbox_token}@#{domain}"
  end

  # Gmail's request to confirm forwarding (a link, or a code from older Gmail), while it's still
  # useful: under 7 days old and no 台電 email forwarded by a filter since
  def pending_forwarding_confirmation?
    (forwarding_link.present? || forwarding_code.present?) && forwarding_code_at&.after?(Utilities::ForwardedMail::LINK_KEPT.ago) &&
      !(last_success_at && last_success_at > forwarding_code_at)
  end

  # The day the last 台電 bill was issued (its 收費日, from any email that brought it in), or else
  # the day a filter last forwarded a 台電 email
  def last_mail_on = last_bill_on || last_success_at&.in_time_zone(household.time_zone)&.to_date

  # 台電 bills every 2 months, so its next email is due 2 months after the last bill (or after
  # Electricity was turned on, before any)
  def next_mail_expected_on
    (last_mail_on || created_at&.in_time_zone(household.time_zone)&.to_date)&.+(BILLED_EVERY)
  end

  # When 台電's email is a week late: the day it was expected (the latest such day, if several bills
  # in a row were missed). nil while nothing is late.
  def missing_mail_expected_on(today)
    expected = next_mail_expected_on or return
    return if today < expected + MISSING_AFTER

    expected += BILLED_EVERY while today >= expected + BILLED_EVERY + MISSING_AFTER
    expected
  end

  private

  def allowed_senders_are_emails
    bad = allowed_senders.grep_v(EMAIL)
    errors.add(:allowed_senders, :invalid, emails: bad.join(", ")) if bad.any?
  end
end
