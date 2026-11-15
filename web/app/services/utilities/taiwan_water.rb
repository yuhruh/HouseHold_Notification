module Utilities
  # 台灣自來水公司 (台水)'s 電子帳單 emails, from service@ebillserver.water.gov.tw, once
  # Utilities::ForwardedMail has accepted one for a ledger. Two kinds come:
  #
  # - 帳單通知 ("台灣自來水公司115年10月帳單通知"): a table of 水號, 繳費起始日, 應繳金額, 繳費期限 and
  #   代收期限 → an unpaid bill with its amount and due date
  # - 繳費成功通知 ("台灣自來水公司繳費成功通知"): "您115年10月之水費帳單…已完成繳費" and a table of
  #   水號, 繳費金額 and 用水地址 → that bill, paid (the day the email is read)
  #
  # Both name the billing month, which ties the two together. 台水's query page needs a captcha, so
  # these emails are the only way the app hears about water bills.
  module TaiwanWater
    # One bill from one email. `month` is the first of the billing month; issued_on its 繳費起始日
    # (nil on a paid notice), due_on its 繳費期限 (nil on a paid notice).
    Bill = Data.define(:customer_code, :month, :amount, :due_on, :paid, :issued_on) do
      # The ledger's label for it: the two months ending two months before the billing month, so the
      # 115年10月 bill (meter read late August) is "7月-8月", the same rule as 台電's
      def period
        start = month << 3
        Period.from_months(start.year, start.month, (month << 2).month)
      end

      def ref(customer_code) = "twwater:#{customer_code}:#{month.strftime("%Y-%m")}"
    end

    module Parser
      # "115年10月帳單通知" in the bill's subject, "您115年10月之水費帳單" in the paid notice
      MONTH = /(\d{2,3})\s*年\s*(\d{1,2})\s*月\s*(?:之?\s*水費|帳單通知)/
      COLUMNS = %w[序號 水號 繳費起始日 應繳金額 繳費期限 代收期限 線上繳費連結 備註 繳費金額 用水地址].freeze

      module_function

      # A Bill, or nil when the email isn't one of the two notices or its table can't be read
      def call(mail)
        row = EmailTable.row(mail, COLUMNS) or return
        month = EmailTable.month(mail, MONTH) or return

        paid = row.key?("繳費金額") && !row.key?("應繳金額")
        code = row["水號"].to_s.strip
        amount = EmailTable.amount(row[paid ? "繳費金額" : "應繳金額"])
        due_on = EmailTable.roc_date(row["繳費期限"]) unless paid
        return unless code.match?(/\A\d{11}\z/) && amount && (paid || due_on)

        Bill.new(customer_code: code, month:, amount:, due_on:, paid:, issued_on: (EmailTable.roc_date(row["繳費起始日"]) unless paid))
      end
    end

    class Reader < BillEmailReader
      PARSER = Parser
      NOTE = "台水 Email 確認繳費".freeze
      EVENTS = { synced: :water_synced, paid: :water_paid }.freeze
      REASON_PREFIX = "water_".freeze
    end
  end
end
