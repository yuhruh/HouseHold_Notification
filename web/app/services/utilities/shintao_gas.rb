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

    # One check for one ledger: both lists from 欣桃, written by Utilities::BillSync
    class Sync
      NOTE = "欣桃天然氣自動確認繳費".freeze
      EVENTS = { synced: :gas_synced, paid: :gas_paid }.freeze

      # The lines it reported, or nil when 欣桃 couldn't be checked (the reason is in last_error)
      def self.call(account, today: Time.current.in_time_zone(account.household.time_zone).to_date, client: Client.new(account.customer_code))
        sync = BillSync.new(account, today:, note: NOTE, events: EVENTS)
        begin
          paid, unpaid = client.paid, client.unpaid
        rescue Error => e
          sync.fail!(e.is_a?(NotFound) ? "not_found" : e.message)
          return nil
        rescue StandardError => e
          sync.fail!(e.message)
          raise
        end
        sync.call(unpaid:, paid:)
      end
    end
  end
end
