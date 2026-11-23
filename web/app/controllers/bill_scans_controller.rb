# New Record → Scan the Bill's Barcodes: the phone sends the three barcodes it read and gets back what
# to fill in. A biller code the household hasn't seen yet comes back unknown, so the form asks once
# which category it is (biller_codes#create) and then asks again here.
#
# Before the form is filled the records are checked: "already" when a record has this bill number,
# "similar" when one without a bill number (typed in by hand) has the same category and period. Either
# way the matching records come back as cards, and choosing a similar one (update) gives it the bill
# number, so the next scan of this bill knows it at once.
class BillScansController < ApplicationController
  include HouseholdScoped
  include BillMatching

  def show
    authorize Record, :create?
    scan = Records::BillBarcode.parse(params[:codes])
    return render json: { ok: false }, status: :unprocessable_content unless scan

    known = Current.household.biller_codes.find_by(code: scan.biller)
    # No billing month on the bill: the months of this category's latest record (地價稅: 1月-12月)
    last = known && !scan.billing_month && last_months(known.category_id)
    due_on = known && (scan.deadline - known.deadline_offset_days)
    year = scan.billing_year || (due_on || scan.deadline).year
    months = scan.billing_month ? [ scan.billing_month ] * 2 : last
    match, matches = bill_matches(bill_number: scan.bill_number, category_id: known&.category_id, year:, months:)
    render json: {
      ok: true, biller: scan.biller, bill_number: scan.bill_number, amount: scan.amount, deadline: scan.deadline.iso8601,
      known: known.present?, category_id: known&.category_id, deadline_offset_days: known&.deadline_offset_days,
      due_on: due_on&.iso8601, period_year: year, period_month: scan.billing_month, period_months: last,
      match:, matches: match_cards(matches)
    }
  end

  # Yes, Open It: the similar record is this bill, so it keeps the bill number
  def update
    record = Current.household.records.find(params[:record_id])
    authorize record
    return head :unprocessable_content unless Records::BillBarcode::SECOND.match?(params[:bill_number].to_s)
    record.update_columns(bill_number: params[:bill_number], updated_at: Time.current) if record.bill_number.blank?
    head :no_content
  end
end
