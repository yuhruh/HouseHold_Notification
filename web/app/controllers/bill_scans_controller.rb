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

  def show
    authorize Record, :create?
    scan = Records::BillBarcode.parse(params[:codes])
    return render json: { ok: false }, status: :unprocessable_content unless scan

    known = Current.household.biller_codes.find_by(code: scan.biller)
    # No billing month on the bill: the months of this category's latest record (地價稅: 1月-12月)
    last = known && !scan.billing_month && Current.household.records.where(category_id: known.category_id).order(period_year: :desc, period_start_month: :desc).first
    due_on = known && (scan.deadline - known.deadline_offset_days)
    year = scan.billing_year || (due_on || scan.deadline).year
    months = scan.billing_month ? [ scan.billing_month ] * 2 : last && [ last.period_start_month, last.period_end_month ]
    match, matches = matches(scan, known, year, months)
    render json: {
      ok: true, biller: scan.biller, bill_number: scan.bill_number, amount: scan.amount, deadline: scan.deadline.iso8601,
      known: known.present?, category_id: known&.category_id, deadline_offset_days: known&.deadline_offset_days,
      due_on: due_on&.iso8601, period_year: year, period_month: scan.billing_month, period_months: last && months,
      match:, matches: matches.presence && render_to_string(partial: "records/mini_card", collection: matches, as: :record, locals: { with_title: true }, formats: :html)
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

  private

  def matches(scan, known, year, months)
    same_bill = Current.household.records.where(bill_number: scan.bill_number).order(id: :desc).limit(3).to_a
    return [ "already", same_bill ] if same_bill.any?
    return [ nil, [] ] unless known && months

    from = year * 12 + months[0]
    to = year * 12 + months[1] + (months[1] < months[0] ? 12 : 0) # a period across the new year (11月-2月)
    similar = Current.household.records.where(category_id: known.category_id, bill_number: nil)
      .overlapping(from, to).order(id: :desc).limit(3).to_a
    [ similar.any? ? "similar" : nil, similar ]
  end
end
