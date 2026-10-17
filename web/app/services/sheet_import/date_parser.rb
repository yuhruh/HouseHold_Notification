module SheetImport
  module DateParser
    class ParseError < StandardError; end

    SHEETS_EPOCH = Date.new(1899, 12, 30)

    def self.parse(raw)
      text = raw.to_s.unicode_normalize(:nfkc).strip
      return nil if text.empty?

      case text
      when %r{\A(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\z}, /\A(\d{4})年(\d{1,2})月(\d{1,2})日\z/
        Date.new($1.to_i, $2.to_i, $3.to_i)
      when /\A\d{5}\z/ # Sheets serial number
        SHEETS_EPOCH + text.to_i
      else
        raise ParseError, "date #{raw.inspect} is not recognized (expected e.g. 2025/4/14)"
      end
    rescue Date::Error
      raise ParseError, "date #{raw.inspect} is not a valid date"
    end
  end
end
