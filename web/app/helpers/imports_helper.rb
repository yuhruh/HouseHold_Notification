module ImportsHelper
  def import_category_options(record_type, choice)
    existing = Current.household.categories.ordered.where(record_type:).map { |c| [ c.name, c.id.to_s ] }
    suggested_new = choice.to_s.start_with?("new:") ? [ [ t("imports.show.new_category", name: choice.delete_prefix("new:")), choice ] ] : []
    options_for_select(suggested_new + existing, choice)
  end

  def import_value(field, value, currency = "TWD")
    return "–" if value.blank?
    field.start_with?("amount_") ? money(BigDecimal(value), currency) : value
  end

  def import_period(values)
    Period.new(start_year: values["period_year"], start_month: values["period_start_month"],
      end_year: values["period_end_year"], end_month: values["period_end_month"]).to_s
  end
end
