# Recurring templates (PRD §5). Saving changes that touch existing unpaid bills shows a
# confirmation listing each bill before → after; deleting keeps every bill, unlinked.
class RecurringTemplatesController < ApplicationController
  include HouseholdScoped
  before_action :set_template, except: %i[index new create]

  def index
    authorize RecurringTemplate
    @templates = Current.household.recurring_templates.includes(:category).order(:record_type, :title)
    @today = owner_today
  end

  def new
    authorize RecurringTemplate
    @template = Current.household.recurring_templates.new(currency: Current.household.default_currency,
      interval_months: 2, starts_on: Date.current, lead_days: 7)
  end

  def create
    authorize RecurringTemplate
    @template = Current.household.recurring_templates.new(template_params)
    RecurringTemplate.transaction do
      @template.save!
      @result = Recurring::Generator.call(@template, today: owner_today)
    end
    redirect_to household_recurring_templates_path(Current.household), notice: t(".created", count: @result.created.size + @result.linked.size)
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit
    authorize @template
  end

  def update
    authorize @template
    @submitted = template_params
    @change = Recurring::TemplateChange.new(@template, @submitted, today: owner_today)
    return render(:edit, status: :unprocessable_content) unless @change.valid?
    return render(:confirm) if @change.changes.any? && params[:confirmed].blank?

    @change.apply!(user: Current.user)
    redirect_to household_recurring_templates_path(Current.household), notice: t(".saved", count: @change.changes.size)
  end

  def destroy
    authorize @template
    @template.destroy!
    redirect_to household_recurring_templates_path(Current.household), notice: t(".deleted")
  end

  # Resolves "2 bills match this period": link one, or create a new bill for the period
  def link
    authorize @template
    period = @template.period_at(params.require(:period_index).to_i)
    if params[:record_id].present?
      Recurring::Generator.matching_bills(@template, period).find(params[:record_id]).update!(recurring_template: @template)
    else
      Recurring::Generator.new(@template, owner_today).create_bill(period)
    end
    redirect_to household_recurring_templates_path(Current.household), notice: t(".linked")
  end

  private

  def set_template
    @template = Current.household.recurring_templates.find(params[:id])
  end

  def owner_today = Time.use_zone(Current.household.time_zone) { Date.current }

  def template_params
    params.expect(recurring_template: %i[category_id title details currency default_amount amount_fixed interval_months
      anchor_month period_span_months starts_on due_day due_month_offset lead_days default_reminder_frequency payment_method_id])
  end
end
