module RecordsHelper
  # Unpaid stands out in red; overdue is the strongest (solid red)
  STATUS_CLASSES = { paid: "bg-green-100 text-green-800", overdue: "bg-red-600 text-white",
                     partial: "bg-amber-100 text-amber-900", unpaid: "bg-red-100 text-red-700" }.freeze

  def record_status_badge(record)
    status = record.status
    tag.span(t("records.status.#{status}"), class: "whitespace-nowrap rounded px-1.5 py-0.5 text-xs font-medium #{STATUS_CLASSES[status]}")
  end

  # ✅ only when the status is paid (PRD §1 ✅ / ❌ column)
  def record_check(record) = record.status == :paid ? "✅" : "❌"

  def category_options(record)
    categories = Current.household.categories.ordered.where(archived_at: nil).or(Current.household.categories.where(id: record.category_id))
    categories.group_by(&:record_type).map do |type, list|
      [ t("records.types.#{type}"), list.map { |c| [ c.detail_required ? "#{c.name} (#{c.detail_label})" : c.name, c.id ] } ]
    end
  end

  def payment_method_options(record)
    Current.household.payment_methods.where(archived_at: nil).or(Current.household.payment_methods.where(id: record.payment_method_id))
      .order(:name).map { |pm| [ pm.last4.present? ? "#{pm.name} ··#{pm.last4}" : pm.name, pm.id ] }
  end

  def month_options = (1..12).map { |m| [ t("records.month", month: m), m ] }
end
