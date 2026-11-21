module Supplies
  # Add a receipt: one printed e-invoice (its two QR codes) or up to 10 invoice PDFs (their text, read in
  # the browser), reviewed on one screen and saved together. Nothing is stored between the review and
  # the save: both read the same posted QR text or PDF text again.
  #
  # Each invoice becomes an Entry. :ok ones are listed item by item; the rest sit under "Not included"
  # with why: :total_only (no item list; its total can still go to the Ledger), :skip_store (marked
  # "not a supplies store"; can be included anyway), :duplicate (the same invoice twice in this upload),
  # :already (added before) and :unreadable (no invoice found in the PDF, e.g. a scanned photo).
  class ReceiptBatch
    MAX_PDFS = 10

    Entry = Data.define(:key, :file, :receipt, :status, :already, :rows, :store) do
      def included_by_default? = status == :ok
      def items? = rows.present?
    end
    Result = Data.define(:invoices, :purchases, :ledger)

    # params: { source: "qr", left:, right: } or { source: "pdf", pdfs: { "0" => { name:, words: } } }
    def self.from(household, params)
      new(household, params)
    end

    attr_reader :entries, :source
    # What was posted (invoices[key][…]) when Save was refused: the review comes back as it was left
    attr_accessor :posted

    def initialize(household, params)
      @household = household
      @source = params[:source] == "pdf" ? "pdf" : "qr"
      @entries = build(parsed(params))
    end

    def pdfs? = @source == "pdf"
    def shown = @entries.select(&:included_by_default?)
    def not_included = @entries.reject(&:included_by_default?)

    # choices: { "<key>" => { exclude: "1", skip_store: "1", include: "1", ledger_total: "1", store:, lines: { … } } }
    def save(choices, user:, add_to_ledger:)
      invoices = purchases = ledger = 0
      ::ReceiptImport.transaction do
        @entries.each do |entry|
          choice = choice_for(choices, entry)
          mark_not_supplies(entry, choice) if entry.status == :ok && choice["exclude"] == "1" && choice["skip_store"] == "1"
          next unless importing?(entry, choice)

          import = import(entry, choice, user:, add_to_ledger: add_to_ledger || entry.status == :total_only)
          invoices += 1
          purchases += import.purchases.count
          ledger += 1 if import.record
        end
      end
      Result.new(invoices:, purchases:, ledger:)
    end

    # The lines still on "Choose…" on the invoices Save would add, as [entry key, line index]. Save is
    # refused while there are any: a line left out would be lost, since the invoice then counts as added
    def undecided(choices)
      @entries.flat_map do |entry|
        choice = choice_for(choices, entry)
        next [] unless importing?(entry, choice)

        lines = choice["lines"].to_h.stringify_keys
        entry.rows.filter_map { |row| [ entry.key, row.index ] if lines[row.index.to_s].to_h.stringify_keys["choice"].to_s.empty? }
      end
    end

    # What was posted for one invoice, when the review is shown again ({} the first time)
    def posted_for(entry) = choice_for(@posted, entry)

    # Every invoice whose items could be added was added before (or is the same one twice): nothing new
    def all_already? = @entries.any? { it.status == :already } && @entries.all? { it.status.in?(%i[already duplicate]) }

    private

    def choice_for(choices, entry) = choices.to_h.stringify_keys[entry.key].to_h.stringify_keys

    # Whether Save adds this invoice: a listed one unless excluded, one from a store marked "not a
    # supplies store" only when included anyway, one with only a total when its total goes to the Ledger
    def importing?(entry, choice)
      case entry.status
      when :ok then choice["exclude"] != "1"
      when :skip_store then choice["include"] == "1"
      when :total_only then choice["ledger_total"] == "1"
      else false
      end
    end

    def parsed(params)
      if pdfs?
        list = params[:pdfs].respond_to?(:to_unsafe_h) ? params[:pdfs].to_unsafe_h : params[:pdfs].to_h
        list.sort_by { |key, _| key.to_i }.first(MAX_PDFS).map do |_, pdf|
          pdf = pdf.to_h.stringify_keys
          receipt = begin
            InvoicePdfParser.call(pdf["words"].to_s)
          rescue InvoicePdfParser::Invalid
            nil
          end
          [ pdf["name"].to_s.first(120), receipt ]
        end
      else
        [ [ nil, EInvoiceParser.call([ params[:left], params[:right] ].map(&:to_s)) ] ]
      end
    end

    def build(list)
      seen = Set.new
      skipped = @household.receipt_sellers.where(skip: true).pluck(:tax_id).to_set
      list.each_with_index.map do |(file, receipt), index|
        key = index.to_s
        next Entry.new(key:, file:, receipt: nil, status: :unreadable, already: nil, rows: [], store: nil) unless receipt

        already = ImportReceipt.already(@household, receipt)
        status = if !seen.add?(receipt.invoice_no) then :duplicate
        elsif already then :already
        elsif receipt.seller_tax_id && skipped.include?(receipt.seller_tax_id) then :skip_store
        elsif receipt.items.empty? then :total_only
        else :ok
        end
        store = ImportReceipt.store_name(@household, receipt) || receipt.seller_name
        Entry.new(key:, file:, receipt:, status:, already:, rows: ImportReceipt.rows(@household, receipt), store:)
      end
    end

    def import(entry, choice, user:, add_to_ledger:)
      ImportReceipt.call(@household, entry.receipt, lines: choice["lines"].to_h, store: choice["store"].presence || entry.store,
                         user:, add_to_ledger:)
    end

    def mark_not_supplies(entry, choice)
      tax_id = entry.receipt.seller_tax_id or return
      seller = @household.receipt_sellers.find_or_initialize_by(tax_id:)
      seller.update!(name: seller.name.presence || choice["store"].presence || entry.store || tax_id, skip: true)
    end
  end
end
