require "base64"

module Supplies
  # Reads a Taiwan e-invoice proof's (電子發票證明聯) two QR codes. The left one:
  #   0–9 invoice number · 10–16 date (ROC yyyMMdd) · 17–20 random code · 21–28 sales amount (hex)
  #   29–36 total (hex) · 37–44 buyer's tax ID · 45–52 seller's tax ID · 53–76 verification
  #   then ":"-separated: the seller's own area, items in this code, items in all, encoding
  #   (0 Big5, 1 UTF-8, 2 Base64), and name:quantity:unit price for each item.
  # The right one starts with "**" and carries on with the items. A store that prints no item
  # details still gives the total. Returns a Receipt, or raises Invalid.
  class EInvoiceParser
    class Invalid < StandardError; end

    Item = Data.define(:text, :quantity, :unit_price) do
      def amount = (quantity * unit_price).round(2)
    end
    Receipt = Data.define(:invoice_no, :issued_on, :total, :seller_tax_id, :items)

    HEAD = /\A(?<no>[A-Z]{2}\d{8})(?<date>\d{7})(?<random>\d{4})(?<sales>\h{8})(?<total>\h{8})(?<buyer>\d{8})(?<seller>\d{8})/

    def self.call(*codes) = new(codes).call

    # Which of the two a scanned QR is: :left, :right, or nil for anything else
    def self.part(text)
      text = text.to_s
      return :right if text.start_with?("**")
      :left if text.match?(HEAD)
    end

    def initialize(codes)
      codes = codes.flatten.compact.map { it.to_s.strip }.reject(&:empty?)
      @left = codes.find { self.class.part(it) == :left }
      @right = codes.find { self.class.part(it) == :right }
    end

    def call
      head = @left&.match(HEAD) or raise Invalid
      Receipt.new(invoice_no: head[:no], issued_on: date(head[:date]), total: head[:total].to_i(16),
                  seller_tax_id: (head[:seller] unless head[:seller] == "00000000"), items: items)
    end

    private

    def date(text)
      Date.new(text[0, 3].to_i + 1911, text[3, 2].to_i, text[5, 2].to_i)
    rescue Date::Error
      raise Invalid
    end

    def items
      fields = @left.byteslice(77..).to_s.delete_prefix(":")
      _own, _here, _all, encoding, rest = fields.split(":", 5)
      list = [ rest, @right&.delete_prefix("**") ].compact.map { it.delete_prefix(":").delete_suffix(":") }.reject(&:empty?).join(":")
      return [] if list.empty?

      list = decode(list, encoding)
      list.split(":").each_slice(3).filter_map do |name, quantity, price|
        name = name.to_s.squish
        next if name.empty? || quantity.nil? || price.nil?
        quantity = BigDecimal(quantity, exception: false)
        price = BigDecimal(price, exception: false)
        next unless quantity&.positive? && price && !price.negative?
        Item.new(text: name.truncate(100, omission: ""), quantity:, unit_price: price)
      end
    end

    def decode(text, encoding)
      case encoding
      when "2" then Base64.decode64(text).force_encoding("UTF-8").scrub("")
      when "0" then big5(text)
      else text.dup.force_encoding("UTF-8").scrub("")
      end
    end

    # Big5 bytes that arrived as a raw string; text the scanner already decoded passes through
    def big5(text)
      return text if text.dup.force_encoding("UTF-8").valid_encoding? && text.match?(/\p{Han}/)
      text.b.force_encoding("Big5").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    rescue EncodingError
      text.dup.force_encoding("UTF-8").scrub("")
    end
  end
end
