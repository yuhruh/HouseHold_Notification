module Utilities
  # Writes one accepted bill email's bill into the ledger (Utilities::BillSync), for a company whose
  # emails are read by PARSER (Taipower::Reader, TaiwanWater::Reader). The first bill sets the
  # account's customer number when it has none; a bill for any other number is then ignored.
  class BillEmailReader
    def self.call(account, mail, today: Time.current.in_time_zone(account.household.time_zone).to_date)
      new(account, mail, today).call
    end

    def initialize(account, mail, today)
      @account, @mail, @today = account, mail, today
    end

    # The lines BillSync reported, or nil when nothing was written (the reason is in the activity)
    def call
      bill = self.class::PARSER.call(@mail) or return note!("unreadable", @mail.subject.to_s.truncate(100))
      return unless customer_code_fits?(bill)

      # When the next bill is expected (ForwardedBills#next_mail_expected_on); saved with the sync
      @account.last_bill_on = [ @account.last_bill_on, bill.issued_on ].compact.max

      # Only a filter-forwarded email counts as "the filter works" (ForwardedMail sets that)
      BillSync.new(@account, today: @today, note: self.class::NOTE, events: self.class::EVENTS, add_paid: true, touch_success: false)
        .call(**(bill.paid ? { paid: [ bill ] } : { unpaid: [ bill ] }))
    rescue StandardError => e
      Rails.error.report(e, context: { utility_account_id: @account.id })
      @account.reload
      note!("unreadable", @mail.subject.to_s.truncate(100))
    end

    private

    def customer_code_fits?(bill)
      masked = "…#{bill.customer_code.last(4)}"
      if @account.customer_code.nil?
        return ignore!("other_ledger_code", masked) if @account.class.where(customer_code: bill.customer_code).where.not(id: @account.id).exists?

        @account.customer_code = bill.customer_code
        @account.add_activity([ { "kind" => "customer_code_set", "detail" => masked } ])
        @account.save!
      elsif @account.customer_code != bill.customer_code
        return ignore!("other_customer_code", masked)
      end
      true
    end

    # reason: under utilities.forwarded_mail, with the company's prefix (REASON_PREFIX)
    def ignore!(reason, detail)
      @account.add_activity([ { "kind" => "ignored", "reason" => "#{self.class::REASON_PREFIX}#{reason}", "detail" => detail } ])
      @account.save!
      false
    end

    def note!(kind, detail)
      @account.add_activity([ { "kind" => kind, "detail" => detail } ])
      @account.save!
      nil
    end
  end
end
