module Supplies
  # Reads an e-invoice detail PDF (發票明細) a store emails or lets you download. The PDF itself never
  # leaves the browser: pdf.js pulls out its text pieces with where each sits on the page
  # (receipt_pdf_controller), and those come here as [{ "s" => text, "x", "y" (from the top), "w", "h" }].
  #
  # Stores lay these out differently, so nothing is read by fixed position: the invoice number, date,
  # seller and total are found by their patterns and labels, and the items from the table under the
  # heading row with 數量 (quantity) and 金額 (amount). Each row's numbers sit in those columns; a long
  # name wraps over several lines in the name column, and each piece joins the row it's closest to.
  # Returns an EInvoiceParser::Receipt (items may be empty: total only), or raises Invalid.
  class InvoicePdfParser
    class Invalid < StandardError; end

    MAX_WORDS = 5_000

    Word = Data.define(:s, :x, :y, :w, :h) do
      def right = x + w
      def mid_x = x + w / 2
      def mid_y = y + h / 2
    end

    NUMBER = /\A-?[\d,]+(?:\.\d+)?\z/
    INVOICE_NO = /(?<![A-Z])([A-Z]{2})-?(\d{8})(?!\d)/
    QTY_LABEL = /\A(數量|數\s*量|Qty)\z/i
    PRICE_LABEL = /\A(單價|單\s*價|Price)\z/i
    AMOUNT_LABEL = /\A(金額|小計|Amount)\z/i
    NAME_LABEL = /\A(品名|品項|商品名稱|項目|品名\/服務名稱)\z/
    TABLE_END = /總計|合計|銷售額|總金額|其他資訊|稅額|\bTotal\b/i
    TOTAL_LABELS = [ /發票總金額/, /總金額/, /合計/, /總計/, /\A(Grand\s+)?Total\b/i ].freeze
    FIELD = 40 # how far (pt) a number can sit from its column heading
    NAME_LENGTH = 100 # characters of an item's name that are kept

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
      text = lines.map { |line| line.map(&:s).join(" ") }
      number = text.lazy.filter_map { it[INVOICE_NO] }.first or raise Invalid
      issued_on = date(text) or raise Invalid
      items = self.items
      total = self.total || items.sum(&:amount)
      raise Invalid unless total.positive?
      tax_id, name = seller(text)
      EInvoiceParser::Receipt.new(invoice_no: number.delete("-"), issued_on:, total: total.round, seller_tax_id: tax_id, seller_name: name, items:)
    end

    private

    def word(raw)
      return unless raw.is_a?(Hash)
      text = raw["s"].to_s.unicode_normalize(:nfkc).squish
      return if text.empty?
      Word.new(s: text.first(500), x: raw["x"].to_f, y: raw["y"].to_f, w: raw["w"].to_f, h: [ raw["h"].to_f, 1 ].max)
    end

    # Pieces on the same line (their middles within a few points), left to right
    def lines
      @lines ||= @words.each_with_object([]) do |word, list|
        line = list.find { (it.first.mid_y - word.mid_y).abs <= [ it.first.h, word.h ].min / 2.0 }
        line ? line << word : list << [ word ]
      end.each { it.sort_by!(&:x) }.sort_by { it.first.y }
    end

    def date(text)
      text.each do |line|
        if (m = line.match(%r{(20\d{2})\s*[/.\-年]\s*(\d{1,2})\s*[/.\-月]\s*(\d{1,2})}))
          return Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
        elsif (m = line.match(%r{(?<!\d)(1\d{2})\s*[/.年]\s*(\d{1,2})\s*[/.月]\s*(\d{1,2})}))
          return Date.new(m[1].to_i + 1911, m[2].to_i, m[3].to_i)
        end
      rescue Date::Error
        next
      end
      nil
    end

    # "85627834 徠樂企業社" (tax ID then name), or a 賣方/統編 label before the number
    def seller(text)
      text.each do |line|
        if (m = line.match(/\A(\d{8})\s+([^\d\s].{0,59})\z/))
          return [ m[1], m[2].squish ]
        elsif (m = line.match(/(?:賣方|統一編號|統編)[^\d買]{0,6}(\d{8})/)) && !line.include?("買受人")
          return [ m[1], nil ]
        end
      end
      [ nil, nil ]
    end

    # The number on the same line as the strongest total label (發票總金額 before 總計)
    def total
      TOTAL_LABELS.each do |label|
        lines.each do |line|
          at = line.index { it.s.match?(label) } or next
          value = line[(at + 1)..].find { it.s.match?(NUMBER) }
          return BigDecimal(value.s.delete(",")) if value
        end
      end
      nil
    end

    def items
      head = lines.find { |line| line.any? { it.s.match?(QTY_LABEL) } && line.any? { it.s.match?(AMOUNT_LABEL) } } or return []
      columns = { quantity: head.find { it.s.match?(QTY_LABEL) }, unit_price: head.find { it.s.match?(PRICE_LABEL) },
                  amount: head.find { it.s.match?(AMOUNT_LABEL) } }.compact
      # No 品名 heading: the leftmost heading is the name column's, unless it's a number column
      name_label = head.find { it.s.match?(NAME_LABEL) } || head.min_by(&:x).then { it unless columns.value?(it) }
      # The name column ends where the next heading to its right starts (稅別, or 數量 itself)
      name_edge = head.select { it != name_label && it.x > (name_label&.right || 0) }.map(&:x).min - 2
      top = head.map { it.y + it.h }.max
      bottom = lines.find { |line| line.first.y > top && line.any? { it.s.match?(TABLE_END) } }&.first&.y || Float::INFINITY
      body = @words.select { it.y >= top - 1 && it.y < bottom }

      rows = numeric_rows(body.reject { it.x < name_edge }, columns)
      return [] if rows.empty?
      body.select { it.right <= name_edge + 2 }.each do |piece|
        rows.min_by { (it[:y] - piece.mid_y).abs }[:name] << piece
      end
      rows.filter_map { item(it) }
    end

    # Numbers under the quantity / price / amount headings, grouped by line: one per item row
    def numeric_rows(words, columns)
      words.select { it.s.match?(NUMBER) }.each_with_object([]) do |word, rows|
        column, heading = columns.min_by { |_, label| (label.mid_x - word.mid_x).abs }
        next unless heading && (heading.mid_x - word.mid_x).abs <= FIELD
        row = rows.find { (it[:y] - word.mid_y).abs <= word.h / 2.0 } || (rows << { y: word.mid_y, name: [] }).last
        row[column] ||= BigDecimal(word.s.delete(","))
      end.select { it[:amount] || it[:unit_price] }
    end

    def item(row)
      name = join(row[:name])
      return if name.empty?
      quantity = row[:quantity]&.positive? ? row[:quantity] : 1
      price = row[:unit_price] || (row[:amount] / quantity).round(4)
      return if price.negative? # a discount line
      EInvoiceParser::Item.new(text: name.truncate(NAME_LENGTH, omission: ""), quantity:, unit_price: price)
    end

    # A wrapped name back on one line: pieces on a line keep their gaps; lines join without a space
    # unless both sides are Latin letters or digits (Chinese wraps mid-word).
    # Pieces go into one buffer, and it stops once the squished buffer has the NAME_LENGTH characters item
    # keeps (more pieces only add after those). It squishes only each time the buffer doubles, so a row
    # with thousands of pieces costs linear time, not a copy of the whole name per piece.
    def join(pieces)
      name = +""
      check_at = NAME_LENGTH
      before = nil
      pieces.sort_by { [ it.y, it.x ] }.chunk_while { |a, b| (a.mid_y - b.mid_y).abs <= [ a.h, b.h ].min / 2.0 }.each do |line|
        line.each_with_index do |piece, i|
          gap = i.zero? ? before&.s&.match?(/[A-Za-z0-9]\z/) && piece.s.match?(/\A[A-Za-z0-9]/) : piece.x - before.right > 1.5
          name << " " if gap
          name << piece.s
          before = piece
          next if name.bytesize < check_at
          kept = name.squish
          return kept if kept.length >= NAME_LENGTH
          check_at = name.bytesize * 2
        end
      end
      name.squish
    end
  end
end
