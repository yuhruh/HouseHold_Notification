module PaymentMethods
  # "從備註指定付款方式" (TRACKING → Payment methods from notes): the sheet kept how a bill was paid as
  # free text in the note. Finds the payment keywords in the notes of records that have no payment
  # method, suggests one method per keyword, and applies the choices: payment_method is filled only
  # where it is blank and notes never change. A note matching several keywords uses the one listed
  # first. The choices are saved as PaymentKeyword rows, which imports reuse.
  class FromNotes
    # [keyword, suggested new method name, kind], in default priority order. "全支付(玉山ubear)"
    # counts under the card (ubear), so 全支付 itself is not a keyword.
    DICTIONARY = [
      [ "ubear", "玉山 ubear 卡", "card" ], [ "unicard", "玉山 unicard", "card" ], [ "大戶卡", "大戶卡", "card" ],
      [ "新光信用卡", "新光信用卡", "card" ], [ "玉山帳戶", "玉山帳戶", "bank" ], [ "中信轉帳", "中信轉帳", "bank" ],
      [ "街口", "街口支付", "e_wallet" ], [ "Pi錢包", "Pi 錢包", "e_wallet" ], [ "LINE Pay", "LINE Pay", "e_wallet" ],
      [ "Apple Pay", "Apple Pay", "e_wallet" ], [ "Google Pay", "Google Pay", "e_wallet" ], [ "台灣Pay", "台灣 Pay", "e_wallet" ],
      [ "悠遊付", "悠遊付", "e_wallet" ], [ "現金", "現金", "cash" ]
    ].freeze
    SKIP = "skip"
    EXAMPLES = 3

    Keyword = Data.define(:keyword, :choice, :suggestion, :count, :examples)

    def initialize(household)
      @household = household
    end

    # Keywords that match at least one note, in priority order, with their default choice and the
    # number of records each would fill under that order
    def keywords
      @keywords ||= begin
        order = ordered_keywords
        firsts = records.map { |record| order.find { |k| PaymentKeyword.match?(k, record.payment_note) } }
        order.filter_map do |keyword|
          matching = records.select { |r| PaymentKeyword.match?(keyword, r.payment_note) }
          next if matching.empty?
          Keyword.new(keyword:, choice: default_choice(keyword), suggestion: suggestion(keyword),
            count: firsts.count(keyword), examples: matching.map { |r| r.payment_note.squish.truncate(40) }.uniq.first(EXAMPLES))
        end
      end
    end

    # Records with no payment method and a note: the only ones this ever changes
    def records
      @records ||= @household.records.where(payment_method_id: nil).where.not(payment_note: [ nil, "" ]).order(:id).to_a
    end

    # For each record that matches any keyword, the keywords it matches (the page recounts with these)
    def matches = matched.map(&:last)

    # Notes matching two or more keywords: [note, keywords]
    def overlaps = matched.select { |_, list| list.size > 1 }.map { |record, list| [ record.payment_note.squish, list ] }.uniq

    def unmatched_count = records.size - matches.size

    # order: keywords in priority order; choices: keyword => "pm:<id>" | "new:<kind>:<name>" | "skip".
    # Unknown keywords and invalid choices are ignored. Returns { records:, methods: } counts.
    def apply!(order:, choices:, user:)
      known = keywords.map(&:keyword)
      order = order.map(&:to_s).select { |k| known.include?(k) }.uniq
      order += known - order
      created = 0
      filled = 0
      PaymentKeyword.transaction do
        methods = order.to_h do |keyword|
          method = resolve(choices[keyword].presence || default_choice(keyword)) { created += 1 }
          [ keyword, method ]
        end
        save_keywords(order, methods)
        records.each do |record|
          keyword = order.find { |k| methods[k] && PaymentKeyword.match?(k, record.payment_note) }
          next unless keyword
          record.update!(payment_method: methods[keyword])
          RecordEvent.log!(record, :updated, user:)
          filled += 1
        end
      end
      { records: filled, methods: created }
    end

    # The saved method for a note (imports): the first saved keyword in the note, unless it is a skip
    def self.method_for(note, saved_keywords)
      saved_keywords.find { |k| match?(k.keyword, note) }&.payment_method if note.present?
    end

    def self.match?(keyword, note) = PaymentKeyword.match?(keyword, note)

    def suggestion(keyword)
      entry = DICTIONARY.find { |k, _, _| k == keyword }
      entry ? { name: entry[1], kind: entry[2] } : { name: keyword, kind: "other" }
    end

    private

    def matched
      @matched ||= begin
        names = keywords.map(&:keyword)
        records.filter_map { |r| [ r, names.select { |k| PaymentKeyword.match?(k, r.payment_note) } ] }.reject { |_, list| list.empty? }
      end
    end

    def saved = @saved ||= @household.payment_keywords.ordered.includes(:payment_method).to_a

    # Saved keywords keep their order; dictionary keywords not saved yet follow in dictionary order
    def ordered_keywords = (saved.map(&:keyword) + DICTIONARY.map(&:first)).uniq

    def active_methods = @active_methods ||= @household.payment_methods.active.order(:name).to_a

    def default_choice(keyword)
      row = saved.find { |k| k.keyword == keyword }
      if row
        return SKIP if row.payment_method.nil?
        return "pm:#{row.payment_method_id}" if row.payment_method.archived_at.nil?
      end
      found = active_methods.find { |pm| PaymentKeyword.match?(keyword, pm.name) }
      return "pm:#{found.id}" if found
      s = suggestion(keyword)
      existing = active_methods.find { |pm| pm.name == s[:name] }
      existing ? "pm:#{existing.id}" : "new:#{s[:kind]}:#{s[:name]}"
    end

    # The payment method for a choice, or nil for skip / invalid. New methods reuse one of the same name.
    def resolve(choice)
      case choice.to_s
      when /\Apm:(\d+)\z/ then active_methods.find { |pm| pm.id == $1.to_i }
      when /\Anew:([a-z_]+):(.+)\z/m
        kind, name = $1, $2.strip.first(40)
        return nil unless PaymentMethod.kinds.key?(kind) && name.present?
        @household.payment_methods.find_by(name:, archived_at: nil) ||
          @household.payment_methods.create!(name:, kind:).tap { yield }
      end
    end

    def save_keywords(order, methods)
      order.each_with_index do |keyword, position|
        @household.payment_keywords.find_or_initialize_by(keyword:).update!(payment_method: methods[keyword], position:)
      end
    end
  end
end
