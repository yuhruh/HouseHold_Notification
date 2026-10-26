module RecordsHelper
  # Unpaid stands out in red; overdue is the strongest (solid red)
  STATUS_CLASSES = { paid: "bg-green-100 text-green-800", overdue: "bg-red-600 text-white",
                     partial: "bg-amber-100 text-amber-900", unpaid: "bg-red-100 text-red-700" }.freeze

  # Records list cards that still need paying get a light tint (red when overdue); paid cards stay white.
  # Dark mode: a softer tint (classes are written out in full so Tailwind finds them)
  CARD_CLASSES = { paid: "bg-white", unpaid: "bg-amber-50 dark:bg-amber-50/60",
                   partial: "bg-amber-50 dark:bg-amber-50/60", overdue: "bg-red-50 dark:bg-red-50/60" }.freeze

  def record_card_class(record) = CARD_CLASSES[record.status]

  # A record type's name with its picture in front (icons/expense.png, maintenance.png, tax.png), sized to the
  # surrounding text
  def record_type_label(type)
    safe_join([ image_tag("icons/#{type}.png", alt: "", class: "inline h-[1.2em] w-[1.2em] object-contain align-[-0.25em]"), " ", t("records.types.#{type}") ])
  end

  def record_status_badge(record)
    status = record.status
    label = record.maintenance? ? t("records.maintenance_status.#{status}") : t("records.status.#{status}")
    tag.span(label, class: "whitespace-nowrap rounded px-1.5 py-0.5 text-xs font-medium #{STATUS_CLASSES[status]}")
  end

  # The record page's status line: what state the bill is in and how urgent it is, worked out from
  # the record (amounts, due and paid dates). Returns the headline, the line under it and its look.
  STATUS_LINE_LOOKS = {
    paid: { box: "bg-white", text: "text-green-800", icon: "check" },
    overdue: { box: "bg-red-50 dark:bg-red-50/60", text: "text-red-700", icon: "alert" },
    partial: { box: "bg-amber-50 dark:bg-amber-50/60", text: "text-amber-900", icon: "clock" },
    unpaid: { box: "bg-amber-50 dark:bg-amber-50/60", text: "text-amber-900", icon: "clock" }
  }.freeze

  def record_status_line(record, today = Date.current)
    scope = "records.show.status_line"
    status = record.status(today:)
    return maintenance_status_line(record, status, today, scope) if record.maintenance?

    left = Reminders::Wording.outstanding(record)
    left_text = left && t("#{scope}.left_to_pay", amount: left)
    due_text = record.due_on ? t("#{scope}.due", date: l(record.due_on)) : t("#{scope}.no_due")
    headline, detail =
      case status
      when :paid
        [ t("#{scope}.paid_on", date: l(record.paid_on)),
          [ (money(record.amount_paid, record.currency) if record.amount_paid), record.payment_method&.name ].compact.join(" · ") ]
      when :overdue
        [ [ Reminders::Wording.relative("bill", record.due_on, today).upcase_first, left_text ].compact.join(" · "),
          t("#{scope}.was_due", date: l(record.due_on)) ]
      when :partial
        [ [ t("#{scope}.partly_paid"), left_text ].compact.join(" · "), due_text ]
      else
        [ [ t("#{scope}.not_paid"), (Reminders::Wording.relative("bill", record.due_on, today) if record.due_on) ].compact.join(" · "),
          [ due_text, left_text ].compact.join(" · ") ]
      end
    { headline:, detail: detail.presence, **STATUS_LINE_LOOKS[status] }
  end

  # Maintenance is a task, not a bill: done (with what it cost) or not done yet, with its expected cost
  def maintenance_status_line(record, status, today, scope)
    expected = t("#{scope}.expected_cost", amount: money(record.amount_required, record.currency)) if record.amount_required
    due_text = record.due_on ? t("#{scope}.due", date: l(record.due_on)) : t("#{scope}.no_due")
    headline, detail =
      case status
      when :paid
        [ t("#{scope}.done_on", date: l(record.paid_on)),
          [ (t("#{scope}.spent", amount: money(record.amount_paid, record.currency)) if record.amount_paid), record.payment_method&.name ].compact.join(" · ") ]
      when :overdue
        [ Reminders::Wording.relative("bill", record.due_on, today).upcase_first, [ t("#{scope}.was_due", date: l(record.due_on)), expected ].compact.join(" · ") ]
      else
        [ [ t("#{scope}.not_done"), (Reminders::Wording.relative("bill", record.due_on, today) if record.due_on) ].compact.join(" · "),
          [ due_text, expected ].compact.join(" · ") ]
      end
    { headline:, detail: detail.presence, **STATUS_LINE_LOOKS[status] }
  end

  # Maintenance names its amounts, date and note as a task: Expected Cost, Cost, Done On, Note
  MAINTENANCE_LABELS = { "amount_required" => "expected_cost", "amount_paid" => "cost", "paid_on" => "done_on", "payment_note" => "note" }.freeze

  def record_attr_label(record, attr)
    key = MAINTENANCE_LABELS[attr.to_s] if record.maintenance?
    key ? t("records.show.labels.#{key}") : Record.human_attribute_name(attr)
  end

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

  # Bills › All: the filters in use as [label, url without it], for the tags beside the folded Filters
  # button (the amount filter from the summary has its own tag)
  def filter_chips(filter)
    p = filter.params
    household = Current.household
    labels = {
      q: p[:q] && t("records.index.search_chip", q: p[:q]),
      year: p[:year],
      month: p[:month] && t("date.abbr_month_names")[p[:month].to_i],
      type: p[:type] && t("records.types.#{p[:type]}", default: p[:type]),
      category_id: p[:category_id] && household.categories.find_by(id: p[:category_id])&.name,
      status: p[:status] && t("records.status.#{p[:status]}", default: p[:status]),
      payment_method_id: p[:payment_method_id] && household.payment_methods.find_by(id: p[:payment_method_id])&.name
    }
    labels.compact_blank.map { |key, label| [ label.to_s, household_records_path(household, p.except(key)) ] }
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
