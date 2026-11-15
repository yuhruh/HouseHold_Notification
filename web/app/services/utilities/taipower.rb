module Utilities
  # 台電's 電子帳單 emails, once Utilities::ForwardedMail has accepted one for a ledger. Two kinds come:
  #
  # - 電費通知 ("台電e-Bill115年10月電費通知(電號:…)"): a table of 電號, 收費日, 應繳總金額, 繳費期限,
  #   代收截止日 and 查核碼 → an unpaid bill with its amount and due date
  # - 電費已繳通知 ("台電e-Bill 115年10月電費已繳通知(電號：…)"): 電號, 收費日, 繳付金額 and 繳款方式 →
  #   that bill, paid (the day the email is read, as the email doesn't say when it was paid)
  #
  # Which one it is comes from the table's columns. Both name the billing month ("115年10月電費"),
  # which ties the two together. 收費日 is the day the
  # bill was issued in both, not a payment date. Anything else from 台電 (or a table it can't read)
  # changes nothing and is listed as unreadable.
  module Taipower
    # One bill from one email. `month` is the first of the billing month; issued_on its 收費日;
    # due_on is nil on a paid notice.
    Bill = Data.define(:customer_code, :month, :amount, :due_on, :paid, :issued_on) do
      # The ledger's label for it: the two months ending two months before the billing month, so the
      # 115年10月 bill is "7月-8月" (how the bills were always entered)
      def period
        start = month << 3
        Period.from_months(start.year, start.month, (month << 2).month)
      end

      def ref(customer_code) = "taipower:#{customer_code}:#{month.strftime("%Y-%m")}"
    end

    module Parser
      MONTH = /(\d{2,3})\s*年\s*(\d{1,2})\s*月\s*電費/
      ROC_DATE = %r{\A(\d{2,3})/(\d{1,2})/(\d{1,2})\z}
      AMOUNT = /\A\d{1,3}(?:,\d{3})*\z|\A\d+\z/
      # The table's own column names, as 台電 writes them ("電 號" has a space)
      COLUMNS = %w[電號 收費日 應繳總金額 繳費期限 代收截止日 查核碼 繳付金額 繳款方式].freeze

      module_function

      # A Bill, or nil when the email isn't one of the two notices or its table can't be read
      def call(mail)
        subject = normalize(mail.subject)
        html, text = part(mail, "text/html"), part(mail, "text/plain")
        body = normalize(html ? Nokogiri::HTML(html).text : text)
        row = (html && html_row(html)) || (text && text_row(text)) or return

        month = roc_month(subject[MONTH] ? subject : body) or return
        paid = row.key?("繳付金額")
        code = row["電號"].to_s
        amount = row[paid ? "繳付金額" : "應繳總金額"].to_s
        due_on = roc_date(row["繳費期限"]) unless paid
        return unless code.match?(/\A\d{11}\z/) && amount.match?(AMOUNT) && (paid || due_on)

        Bill.new(customer_code: code, month:, amount: BigDecimal(amount.delete(",")), due_on:, paid:, issued_on: roc_date(row["收費日"]))
      end

      # {column name => value} from the HTML table: the row of known column headers and the row after it
      def html_row(html)
        rows = Nokogiri::HTML(html).css("tr").map { |tr| tr.css("th, td").map { normalize(it.text) } }
        rows.each_cons(2) do |header, values|
          names = header.map { it.delete(" ") }
          return names.zip(values).to_h if (names & COLUMNS).size >= 3 && names.all? { it.in?(COLUMNS) }
        end
        nil
      end

      # The same from the text a mail program made of it: the line of column names, then the values line
      def text_row(text)
        lines = normalize(text, lines: true).lines.map(&:strip).reject(&:empty?)
        lines.each_cons(2) do |header, values|
          names = header.gsub("電 號", "電號").split
          next unless names.size >= 3 && names.all? { it.in?(COLUMNS) }

          return names.zip(values.split(/\s+/, names.size)).to_h
        end
        nil
      end

      def part(mail, type)
        part = mail.multipart? ? mail.all_parts.find { it.mime_type == type && !it.attachment? } : (mail if mail.mime_type == type || (type == "text/plain" && mail.mime_type.nil?))
        part&.decoded.to_s.dup.force_encoding(Encoding::UTF_8).scrub.presence
      rescue Mail::UnknownEncodingType, Encoding::Error
        nil
      end

      # Full-width digits, colons and spaces as plain ones; runs of spaces as one
      def normalize(text, lines: false)
        text = text.to_s.unicode_normalize(:nfkc).tr(" ", " ")
        lines ? text.gsub(/[ \t]+/, " ") : text.gsub(/\s+/, " ").strip
      end

      def roc_month(text)
        year, month = text.match(MONTH)&.captures&.map(&:to_i)
        Date.new(year + 1911, month, 1) if year && (1..12).cover?(month)
      end

      def roc_date(value)
        year, month, day = value.to_s.strip.match(ROC_DATE)&.captures&.map(&:to_i)
        year && Date.valid_date?(year + 1911, month, day) ? Date.new(year + 1911, month, day) : nil
      end
    end

    # Writes one accepted email's bill into the ledger (Utilities::BillSync). The first bill sets the
    # account's 電號 when it has none; a bill for any other 電號 is then ignored.
    class Reader
      NOTE = "台電 Email 確認繳費".freeze
      EVENTS = { synced: :taipower_synced, paid: :taipower_paid }.freeze

      def self.call(account, mail, today: Time.current.in_time_zone(account.household.time_zone).to_date)
        new(account, mail, today).call
      end

      def initialize(account, mail, today)
        @account, @mail, @today = account, mail, today
      end

      # The lines BillSync reported, or nil when nothing was written (the reason is in the activity)
      def call
        bill = Parser.call(@mail) or return note!("unreadable", @mail.subject.to_s.truncate(100))
        return unless customer_code_fits?(bill)

        # When the next bill is expected (ElectricityAccount#next_mail_expected_on); saved with the sync
        @account.last_bill_on = [ @account.last_bill_on, bill.issued_on ].compact.max

        # Only a filter-forwarded email counts as "the filter works" (ForwardedMail sets that)
        BillSync.new(@account, today: @today, note: NOTE, events: EVENTS, add_paid: true, touch_success: false)
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
          return ignore!("other_ledger_code", masked) if ElectricityAccount.where(customer_code: bill.customer_code).where.not(id: @account.id).exists?

          @account.customer_code = bill.customer_code
          @account.add_activity([ { "kind" => "customer_code_set", "detail" => masked } ])
          @account.save!
        elsif @account.customer_code != bill.customer_code
          return ignore!("other_customer_code", masked)
        end
        true
      end

      def ignore!(reason, detail)
        @account.add_activity([ { "kind" => "ignored", "reason" => reason, "detail" => detail } ])
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
end
