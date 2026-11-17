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
      return redirect_to back_path, alert: t("supplies.receipts.already", date: l(already.created_at.to_date, format: :long)), status: :see_other
    end
    @stores = Current.household.supply_purchases.where.not(store: nil).distinct.order(:store).pluck(:store)
    @supplies = Current.household.supplies.active.includes(:category).order(:name)
    @categories = Current.household.supply_categories.active.ordered.to_a
  end

  def create
    authorize Supply, :create?
    return if performed?
    result = @batch.save(params.fetch(:invoices, {}).to_unsafe_h, user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
    notice = if result.invoices.zero? then t(".nothing")
    else t(".saved", count: result.purchases, invoices: t(".invoices", count: result.invoices), ledger: result.ledger.positive? ? t(".with_ledger", count: result.ledger) : "")
    end
    redirect_to household_supplies_path(Current.household), notice:, status: :see_other
  rescue Supplies::ImportReceipt::Duplicate => error
    redirect_to back_path, alert: t("supplies.receipts.already", date: l((error.existing&.created_at || Time.current).to_date, format: :long)), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to back_path, alert: t(".failed", reason: error.message), status: :see_other
  end

  private

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
