# A Taiwan e-invoice (發票) scanned from its two QR codes: #new shows what each line is (remembered,
# suggested or skipped) for the household to check, #create saves it (Supplies::ImportReceipt).
# Nothing but the QR text is sent here; the photo stays on the phone.
class Supplies::ReceiptsController < ApplicationController
  include HouseholdScoped
  before_action :set_receipt

  def new
    authorize Supply, :create?
    return if performed?
    if (@already = Supplies::ImportReceipt.already(Current.household, @receipt))
      return redirect_to scan_household_supplies_path(Current.household, mode: "receipt"),
                         alert: t("supplies.receipts.already", date: l(@already.created_at.to_date, format: :long)), status: :see_other
    end
    @rows = Supplies::ImportReceipt.rows(Current.household, @receipt)
    @store = Supplies::ImportReceipt.store_name(Current.household, @receipt)
    @stores = Current.household.supply_purchases.where.not(store: nil).distinct.order(:store).pluck(:store)
    @supplies = Current.household.supplies.active.order(:name)
  end

  def create
    authorize Supply, :create?
    return if performed?
    import = Supplies::ImportReceipt.call(Current.household, @receipt, lines: params.fetch(:lines, {}).to_unsafe_h, store: params[:store],
                                          user: Current.user, add_to_ledger: params[:add_to_ledger] == "1")
    redirect_to household_supplies_path(Current.household), notice: t(".saved", count: import.purchases.count, ledger: import.record ? t(".with_ledger") : ""),
                                                            status: :see_other
  rescue Supplies::ImportReceipt::Duplicate => error
    redirect_to scan_household_supplies_path(Current.household, mode: "receipt"),
                alert: t("supplies.receipts.already", date: l((error.existing&.created_at || Time.current).to_date, format: :long)), status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to scan_household_supplies_path(Current.household, mode: "receipt"), alert: t(".failed", reason: error.message), status: :see_other
  end

  private

  def set_receipt
    @codes = [ params[:left], params[:right] ].map(&:to_s)
    @receipt = Supplies::EInvoiceParser.call(@codes)
  rescue Supplies::EInvoiceParser::Invalid
    authorize Supply, :create?
    redirect_to scan_household_supplies_path(Current.household, mode: "receipt"), alert: t("supplies.receipts.not_einvoice"), status: :see_other
  end
end
