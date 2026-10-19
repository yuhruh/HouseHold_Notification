module Imports
  # A parsed sheet row as plain JSON-safe values: what the preview stores, what import_snapshot
  # keeps as the base for three-way updates, and what the digest is computed from.
  module SheetRow
    FIELDS = %w[item details period_year period_start_month period_end_year period_end_month currency
                amount_required amount_paid paid_on payment_note next_due_on].freeze

    module_function

    def from_parser(row)
      period = row.period
      {
        "item" => row.item, "details" => row.details, "period_year" => period.start_year, "period_start_month" => period.start_month,
        "period_end_year" => period.end_year, "period_end_month" => period.end_month, "currency" => row.currency,
        "amount_required" => decimal(row.required), "amount_paid" => decimal(row.paid), "paid_on" => row.finished_on&.iso8601,
        "payment_note" => row.note, "next_due_on" => row.next_due_on&.iso8601
      }
    end

    # The same shape read from a record, for the "app" side of a three-way comparison
    def from_record(record, item:)
      record.attributes.slice(*FIELDS).merge(
        "item" => item, "amount_required" => decimal(record.amount_required), "amount_paid" => decimal(record.amount_paid),
        "paid_on" => record.paid_on&.iso8601, "next_due_on" => record.next_due_on&.iso8601
      )
    end

    def digest(record_type, values) = Digest::SHA256.hexdigest([ record_type, values.values_at(*FIELDS) ].to_json)

    # Record attributes for these values (item maps to a category separately)
    def record_attributes(values) = values.except("item")

    def decimal(amount) = amount&.to_d&.to_s("F")
  end
end
