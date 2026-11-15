module Utilities
  # Reading a utility company's bill email (台電, 台水): the HTML or plain-text part, the row of
  # values under a row of known column names, and ROC dates like 115/10/21.
  module EmailTable
    ROC_DATE = %r{\A(\d{2,3})/(\d{1,2})/(\d{1,2})\z}
    AMOUNT = /\A\d{1,3}(?:,\d{3})*\z|\A\d+\z/

    module_function

    # {column name => value} from the email: its HTML table, or else the text a mail program made of it
    def row(mail, columns)
      html, text = part(mail, "text/html"), part(mail, "text/plain")
      (html && html_row(html, columns)) || (text && text_row(text, columns))
    end

    # The email's text, for the sentence that names the billing month
    def text(mail)
      html = part(mail, "text/html")
      normalize(html ? Nokogiri::HTML(html).text : part(mail, "text/plain"))
    end

    # The row of known column headers (at least 3, all known) and the row after it
    def html_row(html, columns)
      rows = Nokogiri::HTML(html).css("tr").map { |tr| tr.css("th, td").map { normalize(it.text) } }
      rows.each_cons(2) do |header, values|
        names = header.map { it.delete(" ") }
        return names.zip(values).to_h if (names & columns).size >= 3 && names.all? { it.in?(columns) }
      end
      nil
    end

    # The line of column names, then the values line. A column name may have spaces inside ("電 號").
    def text_row(text, columns)
      lines = normalize(text, lines: true).lines.map(&:strip).reject(&:empty?)
      lines.each_cons(2) do |header, values|
        names = columns.reduce(header) { |line, name| line.gsub(name.chars.join(" "), name) }.split
        next unless names.size >= 3 && names.all? { it.in?(columns) }

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
      text = text.to_s.unicode_normalize(:nfkc).tr(" ", " ")
      lines ? text.gsub(/[ \t]+/, " ") : text.gsub(/\s+/, " ").strip
    end

    # The billing month, as the first of it: from the subject, or else the email's text. `pattern`
    # captures the ROC year and the month ("115年10月電費").
    def month(mail, pattern)
      subject = normalize(mail.subject)
      year, month = (subject.match(pattern) || text(mail).match(pattern))&.captures&.map(&:to_i)
      Date.new(year + 1911, month, 1) if year && (1..12).cover?(month)
    end

    def roc_date(value)
      year, month, day = value.to_s.strip.match(ROC_DATE)&.captures&.map(&:to_i)
      year && Date.valid_date?(year + 1911, month, day) ? Date.new(year + 1911, month, day) : nil
    end

    def amount(value)
      value = value.to_s.strip
      BigDecimal(value.delete(",")) if value.match?(AMOUNT)
    end
  end
end
