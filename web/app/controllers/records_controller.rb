# Records CRUD and one-tap mark-paid (PRD §1, §2). Every write goes through save! and logs a
# record_events row in the same transaction.
class RecordsController < ApplicationController
  include HouseholdScoped
  before_action :set_record, except: %i[index new create]

  def index
    authorize Record
    @filter = Records::Filter.new(Current.household, params.permit(*Records::Filter::KEYS))
  end

  def show
    authorize @record
    @events = Current.household.record_events.where(record_id: @record.id).includes(:user).order(created_at: :desc)
  end

  def new
    authorize Record
    today = Date.current
    @record = Current.household.records.new(currency: Current.household.default_currency, period_year: today.year,
      period_start_month: today.month, period_end_month: today.month)
  end

  def create
    authorize Record
    @record = Current.household.records.new(created_by: Current.user)
    assign(@record)
    if save_with_event(@record, :created)
      redirect_to household_record_path(Current.household, @record), notice: t(".created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @record
  end

  def update
    authorize @record
    assign(@record)
    if save_with_event(@record, :updated)
      redirect_to household_record_path(Current.household, @record), notice: t(".saved")
    else
      render :edit, status: :unprocessable_content
    end
  rescue ActiveRecord::StaleObjectError
    @record.errors.add(:base, t(".stale"))
    render :edit, status: :conflict
  end

  def destroy
    authorize @record
    Record.transaction do
      RecordEvent.log!(@record, :deleted, user: Current.user)
      @record.destroy!
    end
    redirect_to household_records_path(Current.household), notice: t(".deleted")
  end

  # GET asks for the bill amount when Required is blank (not needed for Maintenance)
  def mark_paid
    authorize @record
    return render :mark_paid unless request.post?

    if @record.amount_required.nil? && !@record.maintenance?
      amount = params[:amount].presence or return render(:mark_paid, status: :unprocessable_content)
      @record.amount_required = @record.amount_paid = amount
    elsif @record.amount_required && (@record.amount_paid.nil? || @record.amount_paid < @record.amount_required)
      @record.amount_paid = @record.amount_required
    end
    @record.paid_on = Date.current

    if save_with_event(@record, :marked_paid)
      redirect_back_or_to household_records_path(Current.household), notice: t(".done", title: @record.title)
    else
      render :mark_paid, status: :unprocessable_content
    end
  end

  private

  def set_record
    @record = Current.household.records.find(params[:id])
  end

  def assign(record)
    record.assign_attributes(params.expect(record: %i[category_id title details period_year period_start_month period_end_month
      currency amount_required amount_paid due_on paid_on payment_method_id payment_note next_due_on reminder_frequency
      reminder_starts_on lock_version]))
    record.record_type = record.category&.record_type
  end

  def save_with_event(record, action)
    Record.transaction do
      record.save!
      RecordEvent.log!(record, action, user: Current.user)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end
