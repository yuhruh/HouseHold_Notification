# "+ New payment method…", the last choice on a form's Payment Method menu (payment_method_id "new"): the
# method typed in under it is added with the form's own save, so it shows in Settings › Payment Methods
# right away. A name the household already has (ignoring case and spaces) picks that one instead.
module InlinePaymentMethod
  extend ActiveSupport::Concern
  NEW = "new"

  private

  # For `scope`'s form: an existing method with the typed name, a new unsaved one, or nil when "new"
  # wasn't chosen. Adding one needs the same permission as Settings › Payment Methods
  def inline_payment_method(scope)
    return unless params.dig(scope, :payment_method_id) == NEW

    attrs = params.fetch(:new_payment_method, {}).permit(:name, :kind, :last4)
    name = attrs[:name].to_s.squish
    existing = Current.household.payment_methods.active.find_by("LOWER(name) = ?", name.downcase) if name.present?
    return existing if existing

    authorize PaymentMethod, :create?
    Current.household.payment_methods.new(name:, kind: attrs[:kind].presence || "other",
      last4: (attrs[:last4].to_s.strip.presence if attrs[:kind].in?(PaymentMethod::KINDS_WITH_LAST4)))
  end

  # A new method that can't be saved: its problems shown on the form, nothing saved
  def inline_payment_method_invalid?(method, form_model)
    return false unless method&.new_record? && method.invalid?

    method.errors.full_messages.each { |message| form_model.errors.add(:base, t("payment_methods.inline.error", message:)) }
    true
  end

  def inline_payment_method_notice(notice, method)
    method&.previously_new_record? ? "#{notice}#{t("payment_methods.inline.added", name: method.label)}" : notice
  end
end
