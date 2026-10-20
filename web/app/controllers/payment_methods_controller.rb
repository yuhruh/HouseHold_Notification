# Payment methods CRUD + archive (PRD §4). Archived ones stay on old records but leave the form.
class PaymentMethodsController < ApplicationController
  include HouseholdScoped
  before_action :set_payment_method, only: %i[edit update archive]

  def index
    authorize PaymentMethod
    @payment_methods = Current.household.payment_methods.order(Arel.sql("archived_at IS NOT NULL"), :name)
  end

  def new
    authorize PaymentMethod
    @payment_method = Current.household.payment_methods.new
  end

  def create
    authorize PaymentMethod
    @payment_method = Current.household.payment_methods.new(payment_method_params)
    if @payment_method.save
      redirect_to household_payment_methods_path(Current.household), notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @payment_method
  end

  def update
    authorize @payment_method
    if @payment_method.update(payment_method_params)
      redirect_to household_payment_methods_path(Current.household), notice: t(".saved")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Toggles archived
  def archive
    authorize @payment_method
    @payment_method.update!(archived_at: @payment_method.archived_at ? nil : Time.current)
    redirect_to household_payment_methods_path(Current.household)
  end

  # 從備註指定付款方式: one choice per payment keyword found in notes
  def from_notes
    authorize PaymentMethod
    @plan = PaymentMethods::FromNotes.new(Current.household)
  end

  def assign_from_notes
    authorize PaymentMethod
    choices = params[:choices].respond_to?(:to_unsafe_h) ? params[:choices].to_unsafe_h.transform_values(&:to_s) : {}
    result = PaymentMethods::FromNotes.new(Current.household).apply!(order: Array(params[:keywords]), choices:, user: Current.user)
    redirect_to household_payment_methods_path(Current.household), notice: t(".done", records: result[:records], methods: result[:methods])
  end

  private

  def set_payment_method
    @payment_method = Current.household.payment_methods.find(params[:id])
  end

  def payment_method_params = params.expect(payment_method: %i[name kind last4])
end
