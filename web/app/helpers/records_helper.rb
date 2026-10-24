module RecordsHelper
  # Unpaid stands out in red; overdue is the strongest (solid red)
  STATUS_CLASSES = { paid: "bg-green-100 text-green-800", overdue: "bg-red-600 text-white",
                     partial: "bg-amber-100 text-amber-900", unpaid: "bg-red-100 text-red-700" }.freeze

  # Records list cards that still need paying get a light tint (red when overdue); paid cards stay white.
  # Dark mode: a softer tint (classes are written out in full so Tailwind finds them)
  CARD_CLASSES = { paid: "bg-white", unpaid: "bg-amber-50 dark:bg-amber-50/60",
                   partial: "bg-amber-50 dark:bg-amber-50/60", overdue: "bg-red-50 dark:bg-red-50/60" }.freeze

  def record_card_class(record) = CARD_CLASSES[record.status]

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

  # New records start with the payment method of the household's latest record in the same
  # category (latest paid first): { "category_id" => payment_method_id }, active methods only
  def last_payment_methods
    active = Current.household.payment_methods.active.pluck(:id).to_set
    Current.household.records.where.not(payment_method_id: nil).order(Arel.sql("paid_on DESC NULLS LAST"), id: :desc)
      .pluck(:category_id, :payment_method_id).each_with_object({}) { |(category, pm), map| map[category.to_s] ||= pm if active.include?(pm) }
  end

  # Page numbers to link: the first, the last and two either side of the current one; nil = a gap
  def page_window(page, pages)
    shown = ([ 1, pages ] + ((page - 2)..(page + 2)).to_a).select { |n| n.between?(1, pages) }.uniq.sort
    shown.each_with_object([]) { |n, list| list << nil if list.any? && n > list.last + 1; list << n }
  end

  def month_options = (1..12).map { |m| [ t("date.abbr_month_names")[m], m ] }

  # Amount field value and step: whole numbers for TWD (1536, not 1536.0), cents otherwise
  def amount_value(amount, currency) = Household::WHOLE_CURRENCIES.include?(currency) && amount ? amount.round.to_i : amount
  def amount_step(currency) = Household::WHOLE_CURRENCIES.include?(currency) ? "1" : "0.01"

  # A summary Required / Paid amount that lists the records it adds up (current filters kept)
  def amount_link(row, params, column)
    value = row.public_send(column)
    amount = money(value, row.currency)
    return amount unless value.positive?

    link_to amount, household_records_path(Current.household, params.merge({ amount: column.to_s, type: row.record_type, currency: row.currency }.compact)),
      class: "underline", title: t("records.index.show_#{column}")
  end
end
