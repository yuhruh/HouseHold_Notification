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
      # The table's own column names, as 台電 writes them ("電 號" has a space)
      COLUMNS = %w[電號 收費日 應繳總金額 繳費期限 代收截止日 查核碼 繳付金額 繳款方式].freeze

      module_function

      # A Bill, or nil when the email isn't one of the two notices or its table can't be read
      def call(mail)
        row = EmailTable.row(mail, COLUMNS) or return
        month = EmailTable.month(mail, MONTH) or return

        paid = row.key?("繳付金額")
        code = row["電號"].to_s
        amount = EmailTable.amount(row[paid ? "繳付金額" : "應繳總金額"])
        due_on = EmailTable.roc_date(row["繳費期限"]) unless paid
        return unless code.match?(/\A\d{11}\z/) && amount && (paid || due_on)

        Bill.new(customer_code: code, month:, amount:, due_on:, paid:, issued_on: EmailTable.roc_date(row["收費日"]))
      end
    end

    class Reader < BillEmailReader
      PARSER = Parser
      NOTE = "台電 Email 確認繳費".freeze
      EVENTS = { synced: :taipower_synced, paid: :taipower_paid }.freeze
      REASON_PREFIX = "".freeze
    end
  end
end
