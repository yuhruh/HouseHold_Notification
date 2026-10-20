module PaymentMethodsHelper
  # 從備註指定付款方式: existing methods, "＋ new: <suggestion>", or skip
  def note_keyword_options(plan, keyword)
    methods = Current.household.payment_methods.active.order(:name)
    suggestion = plan.suggestion(keyword.keyword)
    options = []
    unless methods.any? { |pm| pm.name == suggestion[:name] }
      options << [ t("payment_methods.from_notes.new_method", name: suggestion[:name], kind: t("payment_methods.kinds.#{suggestion[:kind]}")),
                   "new:#{suggestion[:kind]}:#{suggestion[:name]}" ]
    end
    options += methods.map { |pm| [ pm.last4.present? ? "#{pm.name} ··#{pm.last4}" : pm.name, "pm:#{pm.id}" ] }
    options << [ t("payment_methods.from_notes.skip"), PaymentMethods::FromNotes::SKIP ]
    options_for_select(options, keyword.choice)
  end
end
