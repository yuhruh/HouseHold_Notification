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

    # One review row: the receipt line, and what it is (a supply, :new, or :skip) and why
    Row = Data.define(:index, :item, :supply, :choice, :tag, :units_per_line)

    def self.already(household, receipt) = household.receipt_imports.find_by(invoice_no: receipt.invoice_no)

    # The store name for the receipt: the one this household gave the seller, if any
    def self.store_name(household, receipt)
      household.receipt_sellers.find_by(tax_id: receipt.seller_tax_id)&.name if receipt.seller_tax_id
    end

    # Lines that aren't things you keep in stock: shipping and handling fees start out skipped
    FEE = /運費|運送費|配送費|手續費|處理費|包裝費|shipping|delivery fee|handling/i

    # What each line probably is: remembered from an earlier receipt from this store, else a fee
    # (skipped), else a name that matches one of the household's supplies, else nothing chosen yet
    def self.rows(household, receipt)
      supplies = household.supplies.active.to_a
      matches = household.receipt_item_matches.where(seller_tax_id: receipt.seller_tax_id.to_s, receipt_text: receipt.items.map(&:text)).index_by(&:receipt_text)
      receipt.items.each_with_index.map do |item, index|
        if (match = matches[item.text])
          supply = supplies.find { it.id == match.supply_id }
          Row.new(index:, item:, supply:, choice: supply ? supply.id.to_s : "skip", tag: supply ? :remembered : :skipped, units_per_line: match.units_per_line)
        elsif item.text.match?(FEE)
          Row.new(index:, item:, supply: nil, choice: "skip", tag: :fee, units_per_line: 1)
        elsif (supply = suggest(supplies, item.text))
          Row.new(index:, item:, supply:, choice: supply.id.to_s, tag: :suggested, units_per_line: 1)
        else
          Row.new(index:, item:, supply: nil, choice: "", tag: nil, units_per_line: 1)
        end
      end
    end

    def self.suggest(supplies, text)
      text = text.downcase
      supplies.find { text.include?(it.name.downcase) || it.name.downcase.include?(text) } ||
        supplies.max_by { overlap(it.name.downcase, text) }.then { it if it && overlap(it.name.downcase, text) >= 0.6 }
    end

    # Share of the name's characters that also appear in the receipt text (receipt names are cut short)
    def self.overlap(name, text)
      letters = name.gsub(/\s/, "").chars.uniq
      letters.empty? ? 0 : letters.count { text.include?(it) }.fdiv(letters.size)
    end

    # lines: { "0" => { choice: "<supply id>" | "new" | "skip", quantity:, units_per_line:, name:, kind:, unit: } }
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
      purchase = LogPurchase.call(supply, { quantity: quantity * units, total_price: total, store: @store,
                                            purchased_on: @receipt.issued_on, receipt_import: import }, user: @user)
      raise ActiveRecord::RecordInvalid, purchase unless purchase.persisted?
    end

    def new_supply(item, line)
      @household.supplies.create!(name: line["name"].presence || item.text.truncate(60, omission: ""),
                                  kind: line["kind"].presence_in(Supply::KINDS) || "other", unit: line["unit"].presence_in(Supply::UNITS) || "piece",
                                  level: 0, created_by: @user)
    end
  end
end
