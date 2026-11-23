# New Record → Choose Bill PDF: the PDF is read on the device (pdf.js, in bill_scan_controller.js) and only
# its text pieces come here. Records::BillPdfParser says what they mean, and the answer fills the form the
# way bill_scans#show does for barcodes: the same "already" / "similar" checks, and a biller seen for the
# first time asks once which category it is (biller_codes#create, its code "T" + its tax ID).
#
# A bill from a biller the parser hasn't learned is read by its labels only: no title or category, and
# every field is a guess. A POST, because the text of a PDF is too long for a URL.
class BillPdfsController < ApplicationController
  include HouseholdScoped
  include BillMatching

  def create
    authorize Record, :create?
    bill = Records::BillPdfParser.call(params[:words].to_s)
    known = bill.biller && Current.household.biller_codes.find_by(code: bill.biller)
    months = bill.period_from ? [ bill.period_from.month, bill.period_to.month ] : (known && last_months(known.category_id))
    year = bill.period_from&.year || bill.due_on.year
    match, matches = bill_matches(bill_number: bill.bill_number, category_id: known&.category_id, year:, months:)
    render json: {
      ok: true, source: "pdf", learned: bill.learned?, known: !bill.learned? || known.present?,
      biller: bill.biller, biller_name: bill.name, title: bill.name, details: bill.account,
      amount: bill.amount.frac.zero? ? bill.amount.to_i : bill.amount.to_f, due_on: bill.due_on.iso8601, deadline: bill.due_on.iso8601,
      category_id: known&.category_id, suggested_category_id: suggested_category(bill)&.id,
      period_year: year, period_months: months,
      period_note: bill.period_from && [ bill.period_from, bill.period_to ].map { "#{it.month}/#{it.day}" },
      bill_number: bill.bill_number, autopay: bill.autopay, match:, matches: match_cards(matches)
    }
  rescue Records::BillPdfParser::Invalid
    render json: { ok: false }, status: :unprocessable_content
  end

  private

  # What a learned biller usually is (中華電信: 網路/電信), offered the first time
  def suggested_category(bill)
    bill.category_name && Current.household.categories.where(record_type: "expense", archived_at: nil).find_by(name_zh: bill.category_name)
  end
end
