module Utilities
  # Writes one utility company's bills into a ledger, for any UtilityAccount. Each provider hands it
  # bills that answer `due_on`, `amount`, `period` (the ledger's label) and `ref(customer_code)`, and
  # optionally `paid_on` (the day it was paid, when the company says). Bills already paid in the app
  # are never changed; nothing is deleted.
  #
  # Each bill is matched to the ledger's bill in the account's category, in this order:
  #   1. the bill the sync created or adopted before (external_ref)
  #   2. the same period label, or a due date within 7 days with the same or no amount
  # One match: unpaid → its amount and due date are filled in; paid → it's marked paid.
  # No match: an unpaid bill is added. Two or more: nothing changes and it's listed to look at.
  class BillSync
    DUE_WINDOW = 7

    # note: added to a bill's payment note when it's marked paid; events: the RecordEvent actions
    # for {synced:, paid:}
    def initialize(account, today:, note:, events:)
      @account, @today, @note, @events = account, today, note, events
      @household = account.household
      @lines = []
    end

    # The lines it reported
    def call(unpaid: [], paid: [])
      Record.transaction do
        @records = @household.records.where(category: @account.category).to_a
        @taken = []
        unpaid.sort_by(&:due_on).each { apply(it, paid: false) }
        paid.sort_by(&:due_on).each { apply(it, paid: true) }
        finish!(error: nil)
      end
      notify_paid
      @lines
    rescue StandardError => e
      fail!(e.message)
      raise
    end

    # The company couldn't be read: keep the reason on the account, change nothing
    def fail!(message)
      @lines = []
      finish!(error: message.to_s.truncate(200))
    end

    private

    # Members hear about bills this sync marked paid, once the transaction has committed
    def notify_paid
      ids = @lines.select { it["kind"] == "paid" }.filter_map { it["record_id"] }
      NotifyBillsPaidJob.perform_later(@household.id, ids) if ids.any?
    end

    def finish!(error:)
      @account.last_checked_at = Time.current
      @account.last_success_at = @account.last_checked_at unless error
      @account.last_error = error
      @account.add_activity(@lines.reject { |line| already_reported?(line) })
      @account.save!
    end

    # Ones that would repeat every day until someone acts aren't listed again
    def already_reported?(line)
      line["kind"].in?(%w[amount_differs needs_a_look]) &&
        @account.activity.any? { it.values_at("kind", "record_id", "period") == line.values_at("kind", "record_id", "period") }
    end

    def apply(bill, paid:)
      ref = bill.ref(@account.customer_code)
      matches = @records.select { it.external_ref == ref }
      matches = candidates(bill) if matches.empty?
      if matches.size > 1
        note(:needs_a_look, bill, record_ids: matches.map(&:id))
      elsif (record = matches.first)
        @taken << record
        update(record, bill, ref, paid:)
      elsif !paid
        create(bill, ref)
      end
    end

    # The same period label (whatever its amount, so a different one gets reported), or a due date
    # within 7 days with the same or no amount; of several, the period label, then the amount decides
    def candidates(bill)
      free = @records.reject { it.external_ref.present? || @taken.include?(it) }
      found = free.select { it.period == bill.period || (near_due?(it, bill) && amount_fits?(it, bill)) }
      [ ->(r) { r.period == bill.period }, ->(r) { r.amount_required == bill.amount } ].each do |rule|
        narrowed = found.select(&rule)
        found = narrowed if found.size > 1 && narrowed.any?
      end
      found
    end

    def near_due?(record, bill) = record.due_on.present? && (record.due_on - bill.due_on).abs <= DUE_WINDOW
    def amount_fits?(record, bill) = record.amount_required.nil? || record.amount_required == bill.amount

    # A bill whose amount isn't the company's is left as it is, paid or not: only listed to look at
    def update(record, bill, ref, paid:)
      if record.amount_required && record.amount_required != bill.amount
        return note(:amount_differs, bill, record:)
      end
      return if record.settled

      record.external_ref ||= ref
      record.amount_required ||= bill.amount
      record.due_on ||= bill.due_on
      if paid
        record.paid_on ||= (bill.paid_on if bill.respond_to?(:paid_on)) || @today
        record.amount_paid = record.amount_required
        record.payment_method ||= @account.payment_method
        record.payment_note = [ record.payment_note, @note ].compact.join("\n") unless record.payment_note.to_s.include?(@note)
      end
      return unless record.changed?

      record.save!
      RecordEvent.log!(record, record.settled ? @events.fetch(:paid) : @events.fetch(:synced), user: nil)
      note(record.settled ? :paid : :matched, bill, record:)
    end

    def create(bill, ref)
      previous = @records.max_by { [ it.period_year, it.period_start_month, it.id ] }
      record = @household.records.create!(record_type: "expense", category: @account.category, details: previous&.details,
        period: bill.period, currency: @household.default_currency, amount_required: bill.amount, due_on: bill.due_on,
        payment_method: @account.payment_method, external_ref: ref)
      RecordEvent.log!(record, @events.fetch(:synced), user: nil)
      @records << record
      @taken << record
      note(:added, bill, record:)
    end

    def note(kind, bill, record: nil, record_ids: nil)
      @lines << { "kind" => kind.to_s, "record_id" => record&.id, "record_ids" => record_ids, "period" => bill.period.to_s,
                  "amount" => bill.amount.to_i, "recorded" => record&.amount_required&.to_i, "due_on" => bill.due_on.iso8601 }.compact
    end
  end
end
