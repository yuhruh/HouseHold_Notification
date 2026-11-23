# Before a scanned or read bill fills New Record, the records are checked: "already" when a record has
# this bill number, "similar" when one without a bill number (typed in by hand) has the same category
# and period. Either way the matching records come back as cards (bill_scans#show, bill_pdfs#create).
module BillMatching
  extend ActiveSupport::Concern

  private

  def bill_matches(bill_number:, category_id:, year:, months:)
    same_bill = bill_number ? Current.household.records.where(bill_number:).order(id: :desc).limit(3).to_a : []
    return [ "already", same_bill ] if same_bill.any?
    return [ nil, [] ] unless category_id && months

    from = year * 12 + months[0]
    to = year * 12 + months[1] + (months[1] < months[0] ? 12 : 0) # a period across the new year (11月-2月)
    similar = Current.household.records.where(category_id:, bill_number: nil)
      .overlapping(from, to).order(id: :desc).limit(3).to_a
    [ similar.any? ? "similar" : nil, similar ]
  end

  def match_cards(matches)
    matches.presence && render_to_string(partial: "records/mini_card", collection: matches, as: :record, locals: { with_title: true }, formats: :html)
  end

  # The months of this category's latest record (a bill that doesn't say its months: 地價稅 1月-12月)
  def last_months(category_id)
    last = Current.household.records.where(category_id:).order(period_year: :desc, period_start_month: :desc).first
    last && [ last.period_start_month, last.period_end_month ]
  end
end
