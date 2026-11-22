module Supplies
  # Saves a reviewed receipt in one transaction: the import row (its invoice number can only be added
  # once per household), the store name for the seller's tax ID, one purchase per matched line
  # (receipt quantity × units per line, e.g. 1 pack = 12 rolls), what each line meant for next time,
  # and, when asked, one Ledger expense for the whole receipt total.
  class ImportReceipt
    class Duplicate < StandardError
      attr_reader :existing
      def initialize(existing) = (@existing = existing) && super()
    end

    # One review row: the receipt line, and what it is (a supply, :new, or :skip) and why. `matched` is
    # the name that matched it: the item's own name (:suggested) or one of its brands (:brand)
    Row = Data.define(:index, :item, :supply, :choice, :tag, :units_per_line, :matched) do
      def initialize(matched: nil, **rest) = super(matched:, **rest)
    end

    # A brand name shorter than this (or a line shorter than this inside a brand name) is too vague to
    # match on: "咖啡" is inside every coffee's name
    BRAND_MIN = 3

    def self.already(household, receipt) = household.receipt_imports.find_by(invoice_no: receipt.invoice_no)

    # The store name for the receipt: the one this household gave the seller, if any
    def self.store_name(household, receipt)
      household.receipt_sellers.find_by(tax_id: receipt.seller_tax_id)&.name if receipt.seller_tax_id
    end

    # Lines that aren't things you keep in stock: shipping and handling fees start out skipped
    FEE = /運費|運送費|配送費|手續費|處理費|包裝費|shipping|delivery fee|handling/i

    # What each line probably is: remembered from an earlier receipt from this store, else a fee
    # (skipped), else a name that matches one of the household's supplies or one of their brands, else
    # nothing chosen yet
    def self.rows(household, receipt)
      supplies = household.supplies.active.to_a
      brands = brand_names(household, supplies)
      matches = household.receipt_item_matches.where(seller_tax_id: receipt.seller_tax_id.to_s, receipt_text: receipt.items.map(&:text)).index_by(&:receipt_text)
      receipt.items.each_with_index.map do |item, index|
        if (match = matches[item.text])
          supply = supplies.find { it.id == match.supply_id }
          Row.new(index:, item:, supply:, choice: supply ? supply.id.to_s : "skip", tag: supply ? :remembered : :skipped, units_per_line: match.units_per_line)
        elsif item.text.match?(FEE)
          Row.new(index:, item:, supply: nil, choice: "skip", tag: :fee, units_per_line: 1)
        elsif (guessed = guess(supplies, brands, item.text))
          supply, matched, tag = guessed
          Row.new(index:, item:, supply:, choice: supply.id.to_s, tag:, units_per_line: 1, matched:)
        else
          Row.new(index:, item:, supply: nil, choice: "", tag: nil, units_per_line: 1)
        end
      end
    end

    # [supply, name] for every product the items were bought or saved as (purchases, old prices,
    # barcodes) and every item combined into them (Supply#former_names): what an item is also called.
    # When two items share a name, the one bought most recently comes first
    def self.brand_names(household, supplies)
      by_id = supplies.index_by(&:id)
      saved = [ household.supply_purchases, household.supply_prices, household.supply_barcodes ].flat_map do |scope|
        scope.where(supply_id: by_id.keys).where.not(product_name: [ nil, "" ]).distinct.pluck(:supply_id, :product_name)
      end
      combined = supplies.flat_map { |supply| supply.former_names.map { [ supply.id, it ] } }
      latest = household.supply_purchases.where(supply_id: by_id.keys).group(:supply_id).maximum(:purchased_on)
      (saved + combined).map { |id, name| [ by_id[id], name.squish ] }.uniq
                        .reject { |supply, name| name.casecmp?(supply.name) }
                        .sort_by { |supply, _| [ -(latest[supply.id]&.jd || 0), supply.id ] }
    end

    # [supply, the name that matched, tag], or nil. In order: an item's or a brand's name exactly; then
    # the longest item or brand name inside the line, or the line inside it (receipt names are cut
    # short), so "Promise Volume Shampoo" wins over "Shampoo"; then a loose guess from the letters an
    # item's name shares with the line. That last one uses item names only, so brands don't add wrong
    # guesses
    def self.guess(supplies, brands, text)
      line = text.to_s.squish.downcase
      return if line.empty?

      named = supplies.map { [ it, it.name, :suggested ] } + brands.map { |supply, name| [ supply, name, :brand ] }
      exact = named.find { |_, name, _| name.downcase == line }
      return exact if exact

      inside = named.select do |_, name, tag|
        name = name.downcase
        (name.include?(line) || line.include?(name)) && (tag == :suggested || [ name.length, line.length ].min >= BRAND_MIN)
      end
      inside.max_by.with_index { |(_, name, _), index| [ name.length, -index ] } ||
        supplies.max_by { overlap(it.name.downcase, line) }.then { [ it, it.name, :suggested ] if it && overlap(it.name.downcase, line) >= 0.6 }
    end

    # Share of the name's characters that also appear in the receipt text (receipt names are cut short)
    def self.overlap(name, text)
      letters = name.gsub(/\s/, "").chars.uniq
      letters.empty? ? 0 : letters.count { text.include?(it) }.fdiv(letters.size)
    end

    # A new supply's Category choice that makes a new category, named in new_category_name
    NEW_CATEGORY = "new".freeze

    # lines: { "0" => { choice: "<supply id>" | "new" | "skip", quantity:, units_per_line:, name:, supply_category_id: (an id or
    # NEW_CATEGORY), new_category_name:, unit: } }
    # (quantity: how many came, when it differs from the receipt; the price stays what the line cost)
    def self.call(household, receipt, lines:, store:, user:, add_to_ledger: false)
      new(household, receipt, lines:, store:, user:, add_to_ledger:).call
    end

    def initialize(household, receipt, lines:, store:, user:, add_to_ledger:)
      @household, @receipt, @lines, @user, @add_to_ledger = household, receipt, lines.to_h.stringify_keys, user, add_to_ledger
      @store = store.to_s.squish.presence
    end

    def call
      existing = self.class.already(@household, @receipt)
      raise Duplicate.new(existing) if existing

      ::ReceiptImport.transaction do
        import = @household.receipt_imports.create!(invoice_no: @receipt.invoice_no, seller_tax_id: @receipt.seller_tax_id,
                                                    issued_on: @receipt.issued_on, total: @receipt.total, created_by: @user)
        remember_store
        @receipt.items.each_with_index { |item, index| save_line(import, item, @lines[index.to_s] || {}) }
        if @add_to_ledger
          import.update!(record: LedgerRecord.call(@household, amount: @receipt.total, paid_on: @receipt.issued_on, currency: @household.default_currency,
                                                   details: [ @store, @receipt.invoice_no ].compact.join(" · "), user: @user))
        end
        import
      end
    rescue ActiveRecord::RecordNotUnique
      raise Duplicate.new(self.class.already(@household, @receipt))
    end

    private

    def remember_store
      return unless @store && @receipt.seller_tax_id
      seller = @household.receipt_sellers.find_or_initialize_by(tax_id: @receipt.seller_tax_id)
      seller.update!(name: @store, skip: false) # imported, so it is a supplies store after all
    end

    def save_line(import, item, line)
      line = line.to_h.stringify_keys
      choice = line["choice"].to_s
      return if choice.empty? # left undecided: not saved, not remembered

      units = [ line["units_per_line"].to_i, 1 ].max
      supply = case choice
      when "skip" then nil
      when "new" then new_supply(item, line)
      else @household.supplies.find(choice)
      end

      match = @household.receipt_item_matches.find_or_initialize_by(seller_tax_id: @receipt.seller_tax_id.to_s, receipt_text: item.text)
      match.update!(supply:, units_per_line: units)
      return unless supply

      total = item.amount
      total = total.round if Household::WHOLE_CURRENCIES.include?(@household.default_currency)
      quantity = line["quantity"].to_s.match?(/\A\d+\z/) && line["quantity"].to_i.positive? ? line["quantity"].to_i : [ item.quantity.round, 1 ].max
      product_name = item.text.to_s.squish.truncate(Priced::PRODUCT_NAME_MAX, omission: "")
      # Bought this product before in packs: the same size as then
      pack_size, pack_unit = supply.pack_size_for(product_name)
      purchase = LogPurchase.call(supply, { quantity: quantity * units, total_price: total, store: @store,
                                            purchased_on: @receipt.issued_on, receipt_import: import,
                                            product_name:, pack_size:, pack_unit: }, user: @user)
      raise ActiveRecord::RecordInvalid, purchase unless purchase.persisted?
    end

    def new_supply(item, line)
      @household.supplies.create!(name: line["name"].presence || item.text.truncate(60, omission: ""),
                                  category: new_supply_category(line), unit: line["unit"].presence_in(Supply::UNITS) || "piece",
                                  level: 0, created_by: @user)
    end

    # "＋ New category…": the one with that name (either language, any case), else a new one at the end of
    # Settings › Categories › Supplies, made in this save (so a refused save makes none)
    def new_supply_category(line)
      return @household.supply_categories.find_by(id: line["supply_category_id"]) unless line["supply_category_id"] == NEW_CATEGORY

      SupplyCategory.named(@household, line["new_category_name"]).tap { raise ActiveRecord::RecordInvalid, it unless it.persisted? }
    end
  end
end
