# New Record → Scan the Bill's Barcodes: the phone sends the three barcodes it read and gets back what
# to fill in. A biller code the household hasn't seen yet comes back unknown, so the form asks once
# which category it is (biller_codes#create) and then asks again here.
class BillScansController < ApplicationController
  include HouseholdScoped

  def show
    authorize Record, :create?
    scan = Records::BillBarcode.parse(params[:codes])
    return render json: { ok: false }, status: :unprocessable_content unless scan

    known = Current.household.biller_codes.find_by(code: scan.biller)
    duplicate = Current.household.records.find_by(bill_number: scan.bill_number)
    # No billing month on the bill: the months of this category's latest record (地價稅: 1月-12月)
    last = known && !scan.billing_month && Current.household.records.where(category_id: known.category_id).order(period_year: :desc, period_start_month: :desc).first
    render json: {
      ok: true, biller: scan.biller, bill_number: scan.bill_number, amount: scan.amount, deadline: scan.deadline.iso8601,
      known: known.present?, category_id: known&.category_id, deadline_offset_days: known&.deadline_offset_days,
      due_on: known && (scan.deadline - known.deadline_offset_days).iso8601,
      period_year: scan.billing_year || (known ? scan.deadline - known.deadline_offset_days : scan.deadline).year,
      period_month: scan.billing_month, period_months: last && [ last.period_start_month, last.period_end_month ],
      duplicate: duplicate && { title: duplicate.title, period: duplicate.period.to_s, url: household_record_path(Current.household, duplicate) }
    }
  end
end
