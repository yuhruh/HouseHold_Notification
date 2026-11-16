module Utilities
  # Gmail's verdict on a message it delivered to the app's mailbox: the Authentication-Results header
  # mx.google.com put on top ("dkim=pass header.i=@gmail.com; spf=pass (…) smtp.mailfrom=…"), read
  # clause by clause.
  #
  # The sender chooses the envelope address, and Gmail quotes it in that header, so nothing is
  # matched across the whole text: comments are dropped, and a value counts only as a property of its
  # own clause. Headers are read from the top of the message as it arrived (Gmail adds its own above
  # anything the sender wrote), and a message whose envelope sender has more than plain address
  # characters proves nothing.
  class AuthenticationResults
    Clause = Data.define(:method, :result, :properties)

    PLAIN_SENDER = /\A<?(?:[\w.+=-]+@[\w.-]+)?>?\z/
    DOMAIN = /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/

    def self.of(mail)
      lines = mail.header.raw_source.to_s.b.gsub(/\r?\n[ \t]+/, " ").lines.map(&:strip)
      google = lines.find { it.match?(/\Aauthentication-results\s*:\s*mx\.google\.com\s*;/i) }.to_s.sub(/\A[^;]*;/, "")
      return_path = lines.find { it.match?(/\Areturn-path\s*:/i) }&.sub(/\A[^:]*:\s*/, "")
      return new("") unless return_path.nil? || return_path.match?(PLAIN_SENDER)

      new(google.force_encoding(Encoding::UTF_8).scrub("?"))
    end

    def initialize(text)
      @clauses = parse(text.to_s)
    end

    # The domains a DKIM signature that passed was made for
    def dkim_domains
      passed("dkim").flat_map { [ it.properties["header.d"], it.properties["header.i"].to_s[/@([^@]*)\z/, 1] ] }
        .compact.map(&:downcase).grep(DOMAIN).uniq
    end

    # A DKIM signature or the From domain's DMARC policy failed
    def failed? = @clauses.any? { it.method.in?(%w[dkim dmarc]) && it.result == "fail" }

    # The envelope sender, when Gmail's SPF check passed for it
    def spf_sender = passed("spf").filter_map { it.properties["smtp.mailfrom"] }.first&.downcase

    private

    def passed(method) = @clauses.select { it.method == method && it.result == "pass" }

    # "method=result name=value …" clauses, split at ";" outside comments and quotes
    def parse(text)
      tokens(text).filter_map do |first, *rest|
        method, result = first.to_s.match(/\A([a-z0-9-]+)=([a-z]+)\z/i)&.captures
        next unless method

        properties = rest.each_with_object({}) do |token, found|
          name, value = token.split("=", 2)
          found[name.downcase] ||= value if value
        end
        Clause.new(method: method.downcase, result: result.downcase, properties:)
      end
    end

    # Each clause's words: a (comment) counts as a space, and a "quoted value" stays in one word
    def tokens(text)
      clauses, words, word, depth, quoted = [], [], +"", 0, false
      finish = -> { words << word unless word.empty?; word = +"" }
      text.each_char do |char|
        if depth.positive? then depth += { "(" => 1, ")" => -1 }.fetch(char, 0)
        elsif quoted then char == '"' ? quoted = false : word << char
        elsif char == '"' then quoted = true
        elsif char == "(" then finish.call; depth = 1
        elsif char == ";" then finish.call; clauses << words; words = []
        elsif char.match?(/\s/) then finish.call
        else word << char
        end
      end
      finish.call
      clauses << words
    end
  end
end
