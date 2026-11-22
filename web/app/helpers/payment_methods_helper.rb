module PaymentMethodsHelper
  # data-* for the element around a Payment Method menu and its "+ New payment method…" fields: the
  # household's active methods by name (lower case), for "You already have …"
  def new_payment_method_data
    existing = Current.household.payment_methods.active.to_h { |pm| [ pm.name.squish.downcase, pm.label ] }
    { controller: "new-payment-method", new_payment_method_existing_value: existing.to_json,
      new_payment_method_same_value: t("payment_methods.inline.already_have", name: "%{name}") }
  end

  # The menu's choice: "new" while a method typed in under it is waiting to be saved
  def payment_method_choice(model) = @new_payment_method&.new_record? ? InlinePaymentMethod::NEW : model.payment_method_id

  # 從備註指定付款方式: existing methods, "＋ new: <suggestion>", or skip
  def note_keyword_options(plan, keyword)
    methods = Current.household.payment_methods.active.order(:name)
    suggestion = plan.suggestion(keyword.keyword)
    options = []
    unless methods.any? { |pm| pm.name == suggestion[:name] }
      options << [ t("payment_methods.from_notes.new_method", name: suggestion[:name], kind: t("payment_methods.kinds.#{suggestion[:kind]}")),
                   "new:#{suggestion[:kind]}:#{suggestion[:name]}" ]
    end
    options += methods.map { |pm| [ pm.label, "pm:#{pm.id}" ] }
    options << [ t("payment_methods.from_notes.skip"), PaymentMethods::FromNotes::SKIP ]
    options_for_select(options, keyword.choice)
  end
end
