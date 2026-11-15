# A utility account whose bills come from the company's emails, forwarded to the ledger's
# ForwardingInbox (ElectricityAccount, WaterAccount). The 11-digit customer number (電號, 水號) is
# optional: the first accepted bill email sets it, and emails for any other number are then
# ignored. Both companies bill every 2 months, so the next email is expected 2 months after the
# last bill, and is late a week after that.
module ForwardedBills
  extend ActiveSupport::Concern

  BILLED_EVERY = 2.months
  MISSING_AFTER = 7.days

  included do
    validates :customer_code, format: { with: /\A\d{11}\z/ }, uniqueness: true, allow_nil: true

    after_create { household.forwarding_inbox || household.create_forwarding_inbox! }
    after_destroy :remove_unused_inbox
  end

  def inbox = household.forwarding_inbox
  def inbox_address = inbox&.address

  # The day the last bill was issued (from any email that brought it in), or else the day a filter
  # last forwarded one of the company's emails
  def last_mail_on = last_bill_on || last_success_at&.in_time_zone(household.time_zone)&.to_date

  # 2 months after the last bill (or after it was turned on, before any)
  def next_mail_expected_on
    (last_mail_on || created_at&.in_time_zone(household.time_zone)&.to_date)&.+(BILLED_EVERY)
  end

  # When the company's email is a week late: the day it was expected (the latest such day, if
  # several bills in a row were missed). nil while nothing is late.
  def missing_mail_expected_on(today)
    expected = next_mail_expected_on or return
    return if today < expected + MISSING_AFTER

    expected += BILLED_EVERY while today >= expected + BILLED_EVERY + MISSING_AFTER
    expected
  end

  private

  # The address stops working once neither Electricity nor Water uses it
  def remove_unused_inbox
    household.reload
    household.forwarding_inbox&.destroy! if household.forwarding_inbox&.mail_accounts&.empty?
  end
end
