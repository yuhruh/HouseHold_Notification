module RecurringTemplatesHelper
  INTERVALS = [ 1, 2, 3, 6, 12, 24 ].freeze

  def interval_label(months)
    case months
    when 1 then t("recurring_templates.every_month")
    when 12 then t("recurring_templates.every_year")
    else t("recurring_templates.every_n_months", count: months)
    end
  end

  def template_amount(template)
    return t("recurring_templates.variable") if template.default_amount.nil?
    label = money(template.default_amount, template.currency)
    template.amount_fixed? ? label : t("recurring_templates.hint", amount: label)
  end

  def template_change_value(key, value, currency)
    case key
    when :amount_required then money(value, currency)
    when :due_on then value ? l(value) : "–"
    else value.to_s
    end
  end
end
