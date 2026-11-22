# Add a receipt: a printed Taiwan e-invoice (its two QR codes) or up to 10 invoice PDFs (發票明細). #new
# shows every item to check (remembered, suggested, a fee skipped, or not found) with the invoices that
# won't be added under "Not included"; #create saves the chosen ones (Supplies::ReceiptBatch). Only the
# QR text or the PDFs' text is sent here; photos and PDF files stay on the device.
class Supplies::ReceiptsController < ApplicationController
  include HouseholdScoped
  before_action :set_batch

  def new
    authorize Supply, :create?
    return if performed?
    if !@batch.pdfs? && (already = @batch.entries.first.already)
      return redirect_to back_path, alert: already_message(already), status: :see_other
    end
    load_review
  end

  def create
    authorize Supply, :create?
    return if performed?
    choices = params.fetch(:invoices, {}).to_unsafe_h
    authorize SupplyCategory, :create? if @batch.new_categories?(choices)
    # A line still on "Choose…": nothing is saved and the review comes back as it was left
    if (undecided = @batch.undecided(choices)).any?
      @undecided = undecided.to_set
      @batch.posted = choices
      load_review
      return render :new, status: :unprocessable_content
    end
    result = @batch.save(choices, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
    notice = if result.invoices.zero? then t(".nothing")
    else t(".saved", count: result.purchases, invoices: t(".invoices", count: result.invoices), ledger: result.ledger.positive? ? t(".with_ledger", count: result.ledger) : "")
    end
    notice += t(".new_categories", count: result.categories.size, names: I18n.locale == :en ? result.categories.to_sentence : result.categories.join("、")) if result.categories.any?
    redirect_to household_supplies_path(Current.household), notice:, status: :see_other
  rescue Supplies::ImportReceipt::Duplicate => error
    redirect_to back_path, alert: already_message(error.existing), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to back_path, alert: t(".failed", reason: error.message), status: :see_other
  end

  private

  def load_review
    @stores = Current.household.supply_purchases.where.not(store: nil).distinct.order(:store).pluck(:store)
    @supplies = Current.household.supplies.active.includes(:category).order(:name)
    @categories = Current.household.supply_categories.active.ordered.to_a
  end

  # "Already added on …", and where its items are now (after a combine, the item they went into)
  def already_message(import)
    message = t("supplies.receipts.already", date: l((import&.created_at || Time.current).to_date, format: :long))
    items = import ? import.purchases.includes(:supply).map { it.supply.name }.uniq : []
    items.any? ? "#{message} #{t('supplies.receipts.already_items', items: items.to_sentence)}" : message
  end

  def set_batch
    @batch = Supplies::ReceiptBatch.from(Current.household, params)
    if @batch.entries.empty?
      authorize Supply, :create?
      redirect_to back_path, alert: t("supplies.receipts.no_pdfs"), status: :see_other
    end
  rescue Supplies::EInvoiceParser::Invalid
    authorize Supply, :create?
    redirect_to back_path, alert: t("supplies.receipts.not_einvoice"), status: :see_other
  end

  def back_path = scan_household_supplies_path(Current.household, mode: params[:source] == "pdf" ? "pdf" : "receipt")
end
