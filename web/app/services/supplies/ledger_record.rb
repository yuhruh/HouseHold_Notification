module Supplies
  # "Also add to Ledger": a paid expense in the 日用品 category for a purchase or a whole receipt
  class LedgerRecord
    CATEGORY = { name_zh: "日用品", name_en: "Household supplies" }.freeze

    def self.category_for(household)
      household.categories.find_or_create_by!(record_type: "expense", name_zh: CATEGORY[:name_zh]) do |category|
        category.name_en = CATEGORY[:name_en]
        category.position = household.categories.where(record_type: "expense").maximum(:position).to_i + 1
      end
    end

    def self.call(household, amount:, paid_on:, details:, currency:, user:)
      period = Period.new(start_year: paid_on.year, start_month: paid_on.month, end_year: paid_on.year, end_month: paid_on.month)
      record = household.records.create!(record_type: "expense", category: category_for(household), details: details.truncate(200),
        period:, currency:, amount_required: amount, amount_paid: amount, paid_on:, created_by: user)
      RecordEvent.log!(record, :created, user:)
      record
    end
  end
end
