module Records
  # New Record › Choose Bill PDF: reads a bill's PDF (繳費通知) from its text. The PDF never leaves the
  # browser: pdf.js pulls out its text pieces with where each sits on the page (bill_scan_controller,
  # as receipt_pdf_controller does for invoices), and those come here as
  # [{ "s" => text, "x", "y" (from the top), "w", "h" }].
  #
  # A biller it has learned (BILLERS, found by its 營利事業統一編號) is read in full: its name and the
  # account number for Details. Any other bill is read by the labels most Taiwan bills print (應繳金額,
  # 繳費期限, 計費期間), and the form tags every field "please check". A value sits either right after its
  # label on the same line ("計費期間：115/09/16至115/10/15") or under it in a table ("繳費期限" over
  # "115/11/10"). Labels are found in each line's joined text, so a PDF that splits its text into single
  # characters still reads.
  #
  # A photo of a bill without barcodes (New Record › Use a Photo) comes the same way: Tesseract reads it on
  # the device and bill_scan_controller sends its words in this shape. A photo can lose a character, so a
  # label may be missing its 費 (繳期限, 計期間) and a 民國 year its first digit.
  #
  # Returns a Bill, or raises Invalid when there is no amount due or no due date (not a bill, or a scan).
  class BillPdfParser
    class Invalid < StandardError; end

    MAX_WORDS = 5_000
    BELOW = 80 # how far (pt) under its label a value can sit
    SIDE = 12  # a piece is in a label's column when its middle is under the label, give or take this (pt) or half the label
    # How many places a label is looked at, at most: a bill prints one a few times, but text made of nothing
    # but labels has hundreds of thousands, and each would be read against its whole line and page
    PLACES = 20

    # Bills read in full, by the biller's tax ID (營利事業統一編號). `account`: the label of the number
    # that tells the household's accounts apart, kept in Details. `category`: the default category
    # (name_zh) offered the first time
    BILLERS = {
      "19683736" => { name: "中華電信", account: "用戶號碼", category: "網路/電信" }
    }.freeze

    Bill = Data.define(:tax_id, :name, :account, :amount, :due_on, :period_from, :period_to, :bill_number, :autopay) do
      def learned? = name.present?
      def biller = tax_id && "T#{tax_id}" # its key in BillerCode
      def category_name = BILLERS.dig(tax_id, :category)
    end

    Word = Data.define(:s, :x, :y, :w, :h) do
      def right = x + w
      def bottom = y + h
      def mid_y = y + h / 2
    end

    DATE = %r{(\d{2,4})/(\d{1,2})/(\d{1,2})|(\d{2,4})[.\-](\d{1,2})[.\-](\d{1,2})|(\d{2,4})年(\d{1,2})月(\d{1,2})日?}
    MONEY = /(?:NT\$|\$)?[\d,]*\d(?:\.\d{1,2})?元?/
    ACCOUNT = /[0-9A-Z]{5,20}/
    AMOUNT_LABELS = /應繳總金額|本期應繳總?金額|應繳金額|應繳總額|繳費金額/
    DUE_LABELS = /繳費?期限|繳款期限|繳費截止日期?|繳款截止日期?|代收期限/
    PERIOD_LABELS = /計費?期間|計費日期|使用期間|帳單期間/
    NUMBER_LABELS = /通知單流水號|繳費單號|帳單號碼/
    AUTOPAY = /定期付款|自動扣繳|自動轉帳|帳戶代繳|信用卡代繳/

    def self.call(words) = new(words).call

    def initialize(words)
      list = words.is_a?(String) ? JSON.parse(words) : words
      raise Invalid unless list.is_a?(Array)
      @words = list.first(MAX_WORDS).filter_map { word(it) }.sort_by { [ it.y, it.x ] }
    rescue JSON::ParserError
      raise Invalid
    end

    def call
      raise Invalid if @words.empty?
      amount = near(AMOUNT_LABELS, MONEY)&.then { BigDecimal(it.delete("NT$,元")) }
      due_on = near(DUE_LABELS, DATE)&.then { date(it) }
      raise Invalid unless amount&.positive? && due_on

      tax_id = inline(/營利事業統一編號:?(\d{8})/) || printed_biller
      biller = BILLERS[tax_id]
      from, to = period
      Bill.new(
        tax_id: biller && tax_id, name: biller&.dig(:name), account: biller && near(/#{biller[:account]}/, ACCOUNT)&.then { "#{biller[:account]} #{it}" },
        amount:, due_on:, period_from: from, period_to: to,
        bill_number: inline(/(?:#{NUMBER_LABELS.source}):?([0-9A-Z]{6,20})/),
        autopay: near(/繳費方式/, AUTOPAY) # "定期付款": paid by itself
      )
    rescue ArgumentError # BigDecimal of a number it couldn't read
      raise Invalid
    end

    private

    def word(item)
      return unless item.is_a?(Hash)
      s = item["s"] || item[:s]
      return unless s.is_a?(String)
      s = s.unicode_normalize(:nfkc).gsub(/\s+/, "") # full-width digits and colons; "定 期 付 款"
      return if s.empty?
      x, y, w, h = %w[x y w h].map { (item[it] || item[it.to_sym]).to_f }
      Word.new(s: s.first(200), x:, y:, w:, h: h.positive? ? h : 10.0)
    end

    # The page's lines: their pieces, left to right
    def lines
      @lines ||= @words.chunk_while { |a, b| (b.mid_y - a.mid_y).abs < [ a.h, b.h ].min / 2 }.map { it.sort_by(&:x) }
    end

    # The first capture in a line's joined text
    def inline(pattern)
      lines.each { |line| (match = pattern.match(line.map(&:s).join)) and return match[1] }
      nil
    end

    # The first value matching `value` that sits right after a `label` on its line, or under it in its
    # column (the closest line there whose pieces in that column, joined, are just the value). Pieces
    # count by their middle, so a wide neighbour that pokes into the column stays out of it
    def near(label, value)
      exact = /\A(?:#{value.source})\z/
      each_label(label) do |box, rest|
        found = rest.match(/\A(?:\(元\))?:?(#{value.source})/)
        return found[1] if found

        under = lines.filter_map do |line|
          next unless line.first.mid_y > box.bottom && line.first.y - box.bottom < BELOW
          reach = [ SIDE, box.w / 2 ].max
          pieces = line.select { |w| (w.x + w.w / 2).between?(box.x - reach, box.right + reach) }
          pieces.map(&:s).join if pieces.any?
        end
        found = under.find { exact.match?(it) }
        return found if found
      end
      nil
    end

    # Each place a label is printed (the first PLACES): a box around the pieces it is made of, and the rest
    # of its line
    def each_label(label)
      places = 0
      lines.each do |line|
        joined = line.map(&:s).join
        joined.scan(label) do
          match = Regexp.last_match
          start = 0
          covered = line.select do |w|
            from = start
            start += w.s.length
            start > match.begin(0) && from < match.end(0)
          end
          left = covered.map(&:x).min
          top = covered.map(&:y).min
          box = Word.new(s: match[0], x: left, y: top, w: covered.map(&:right).max - left, h: covered.map(&:bottom).max - top)
          yield box, joined[match.end(0)..]
          return if (places += 1) >= PLACES
        end
      end
    end

    def period
      line = inline(/(?:#{PERIOD_LABELS.source}):?((?:#{DATE.source})(?:至|~|-|到)(?:#{DATE.source}))/)
      dates = line && line.to_enum(:scan, DATE).map { date(Regexp.last_match[0]) }
      from, to = dates
      from && to && from <= to ? [ from, to ] : [ nil, nil ]
    end

    # A learned biller's tax ID printed anywhere, for a photo whose 營利事業統一編號 label didn't read
    def printed_biller
      text = lines.map { |line| line.map(&:s).join }.join("\n")
      BILLERS.keys.find { text.include?(it) }
    end

    # "115/11/10" (民國) or "2026/11/10". A two-digit year is 民國 1xx: a photo can lose the first digit
    # ("15/11/10"), and no bill today is dated 民國 99 or earlier
    def date(string)
      year, month, day = DATE.match(string)&.captures&.compact&.map(&:to_i)
      return unless day
      year += 100 if year < 100
      year += 1911 if year < 1911
      Date.valid_date?(year, month, day) ? Date.new(year, month, day) : nil
    end
  end
end
