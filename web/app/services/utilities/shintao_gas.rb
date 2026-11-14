module Utilities
  # 欣桃天然氣 (Shintao Gas): the household lookup on shintaogas.com.tw/HOME/invoice/paid. It needs only
  # the 10-digit 用戶編號 and answers JSON. GetPaid lists the bills paid in about the last 2 years,
  # GetUnpaid what's owed now. This is the site's own (undocumented) endpoint, so anything unexpected
  # is an Error, and Sync then changes nothing.
  module ShintaoGas
    HOST = "www.shintaogas.com.tw".freeze
    ZONE = "Asia/Taipei".freeze

    class Error < StandardError; end
    class NotFound < Error; end

    # One bill. `read_from`..`read_to` is the meter period; 限繳日 is `due_on`.
    Bill = Data.define(:due_on, :amount, :read_from, :read_to, :usage) do
      # The ledger's label for it: the two months ending in the month the meter period starts, so
      # 06/05–08/04 is "5月-6月" and 12/05–02/04 is "11月-12月" (how the bills were always entered)
      def period
        start = read_from.beginning_of_month.prev_month
        Period.from_months(start.year, start.month, read_from.month)
      end

      def ref(customer_code) = "shintao:#{customer_code}:#{due_on.iso8601}"
    end

    class Client
      TIMEOUTS = { open_timeout: 5, read_timeout: 15 }.freeze

      def initialize(customer_code)
        @customer_code = customer_code
      end

      def paid = fetch("GetPaid")
      def unpaid = fetch("GetUnpaid")

      # "/Date(1792425600000)/" → that day in Taiwan
      def self.date(value)
        ms = value.to_s[%r{\A/Date\((-?\d+)(?:[+-]\d{4})?\)/\z}, 1] or raise Error, "unexpected date #{value.inspect}"
        Time.at(ms.to_i / 1000).in_time_zone(ZONE).to_date
      end

      def self.bill(item)
        amount = item.fetch("TotalAmt")
        raise Error, "unexpected amount #{amount.inspect}" unless amount.is_a?(Numeric) && amount >= 0
        Bill.new(due_on: date(item.fetch("LIMIT_DATE")), amount: BigDecimal(amount.to_s),
          read_from: date(item.fetch("PRE_REC_DATE")), read_to: date(item.fetch("REC_DATE")), usage: item["USE_QTY"])
      rescue KeyError => e
        raise Error, e.message
      end

      private

      def fetch(action)
        body = post("/HOME/Invoice/#{action}", { CUST_CODE: @customer_code }.to_json)
        json = JSON.parse(body)
        raise Error, "#{action} answered status #{json["Status"].inspect}" unless json.is_a?(Hash) && json["Status"] == 1
        data = json["Data"] or raise NotFound, "#{action}: no customer #{@customer_code}"
        raise Error, "#{action} answered for another customer" unless data["CUST_CODE"].to_s == @customer_code
        Array(data["Details"]).map { self.class.bill(it) }
      rescue JSON::ParserError => e
        raise Error, "#{action}: #{e.message.truncate(80)}"
      end

      def post(path, payload)
        Net::HTTP.start(HOST, 443, use_ssl: true, **TIMEOUTS) do |http|
          request = Net::HTTP::Post.new(path, "Content-Type" => "application/json", "Accept" => "application/json", "User-Agent" => "HouseholdTracker/1.0")
          request.body = payload
          response = http.request(request)
          raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
          response.body
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
        raise Error, "#{e.class}: #{e.message.truncate(80)}"
      end
    end

    # One check for one ledger. Bills already paid in the app are never changed; nothing is deleted.
    # Each gas bill is matched to the ledger's bill in the gas category, in this order:
    #   1. the bill the sync created or adopted before (external_ref)
    #   2. the same period label (see Bill#period), or a due date within 7 days with the same or no amount
    # One match: unpaid → its amount and due date are filled in; paid at 欣桃 → it's marked paid.
    # No match: an unpaid gas bill is added. Two or more: nothing changes and it's listed to look at.
    class Sync
      DUE_WINDOW = 7
      NOTE = "欣桃天然氣自動確認繳費".freeze

      def self.call(account, today: Time.current.in_time_zone(account.household.time_zone).to_date, client: Client.new(account.customer_code))
        new(account, today:, client:).call
      end

      def initialize(account, today:, client:)
        @account, @today, @client = account, today, client
        @household = account.household
        @lines = []
      end

      # The lines it reported, or nil when 欣桃 couldn't be checked (the reason is in last_error)
      def call
        paid, unpaid = @client.paid, @client.unpaid
        Record.transaction do
          @records = @household.records.where(category: @account.category).to_a
          @taken = []
          unpaid.sort_by(&:due_on).each { apply(it, paid: false) }
          paid.sort_by(&:due_on).each { apply(it, paid: true) }
          finish!(error: nil)
        end
        @lines
      rescue Error => e
        fail!(e.is_a?(NotFound) ? "not_found" : e.message)
        nil
      rescue StandardError => e
        fail!(e.message)
        raise
      end

      private

      def fail!(message)
        @lines = []
        finish!(error: message.to_s.truncate(200))
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

      # A bill whose amount isn't 欣桃's is left as it is, paid or not: only listed to look at
      def update(record, bill, ref, paid:)
        if record.amount_required && record.amount_required != bill.amount
          return note(:amount_differs, bill, record:)
        end
        return if record.settled

        record.external_ref ||= ref
        record.amount_required ||= bill.amount
        record.due_on ||= bill.due_on
        if paid
          record.paid_on ||= @today
          record.amount_paid = record.amount_required
          record.payment_method ||= @account.payment_method
          record.payment_note = [ record.payment_note, NOTE ].compact.join("\n") unless record.payment_note.to_s.include?(NOTE)
        end
        return unless record.changed?

        record.save!
        RecordEvent.log!(record, record.settled ? :gas_paid : :gas_synced, user: nil)
        note(record.settled ? :paid : :matched, bill, record:)
      end

      def create(bill, ref)
        previous = @records.max_by { [ it.period_year, it.period_start_month, it.id ] }
        record = @household.records.create!(record_type: "expense", category: @account.category, details: previous&.details,
          period: bill.period, currency: @household.default_currency, amount_required: bill.amount, due_on: bill.due_on,
          payment_method: @account.payment_method, external_ref: ref)
        RecordEvent.log!(record, :gas_synced, user: nil)
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
end
