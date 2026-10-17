module SheetImport
  # Google Sheets exports formatted cells as display strings ("NT$1,234").
  # Returns [BigDecimal or nil, currency or nil]; raises ParseError otherwise.
  module AmountParser
    class ParseError < StandardError; end

    BLANK = [ "", "-", "—", "–" ].freeze
    PREFIXES = { /\A(US\$|USD)/i => "USD", /\A(NT\$|NTD|TWD)/i => "TWD", /\A\$/ => nil }.freeze

    def self.parse(raw)
      text = raw.to_s.unicode_normalize(:nfkc).strip.delete(" ")
      return [ nil, nil ] if BLANK.include?(text)

      raise ParseError, "negative amount #{raw.inspect} (amounts must be ≥ 0)" if text.start_with?("(", "-")

      currency = nil
      PREFIXES.each do |pattern, code|
        next unless text.match?(pattern)
        currency = code
        text = text.sub(pattern, "")
        break
      end
      raise ParseError, "negative amount #{raw.inspect} (amounts must be ≥ 0)" if text.start_with?("-")
      raise ParseError, "amount #{raw.inspect} is not a number" unless text.match?(/\A\d{1,3}(,\d{3})*(\.\d{1,2})?\z|\A\d+(\.\d{1,2})?\z/)

      amount = BigDecimal(text.delete(","))
      raise ParseError, "amount #{raw.inspect} is too large" if amount >= BigDecimal("10000000000")

      [ amount, currency ]
    end
  end
end
