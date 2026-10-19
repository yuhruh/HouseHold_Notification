# Records CRUD and one-tap mark-paid (PRD §1, §2). Every write goes through save! and logs a
# record_events row in the same transaction.
class RecordsController < ApplicationController
  include HouseholdScoped
  before_action :set_record, except: %i[index new create]

  def index
    authorize Record
    @filter = Records::Filter.new(Current.household, params.permit(*Records::Filter::KEYS))
    respond_to do |format|
      format.html
      format.csv do
        send_data Records::CsvExport.new(@filter.records).to_csv, type: "text/csv; charset=utf-8",
          filename: "#{Current.household.name}-records-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    authorize @record
    @events = Current.household.record_events.where(record_id: @record.id).includes(:user).order(created_at: :desc)
    @snooze = ReminderSnooze.find_by(record: @record, user: Current.user)
  end

  def new
    authorize Record
    today = Date.current
    @record = Current.household.records.new(currency: Current.household.default_currency, period_year: today.year,
      period_start_month: today.month, period_end_month: today.month)
  end

  # Maintenance "Done" (PRD §6): a prefilled new record in the same chain, finished today; saving it
  # clears next_due_on on this one
  def done
    authorize @record, :create?
    today = Date.current
    @continues = @record
    @record = Current.household.records.new(@continues.slice(:record_type, :category_id, :title, :details, :payment_method_id, :currency)
      .merge(period_year: today.year, period_start_month: today.month, period_end_month: today.month, paid_on: today))
    render :new
  end

  def restart_reminders
    authorize @record, :update?
    if save_with_event(@record.tap { |r| r.reminders_restarted_on = Date.current }, :reminders_restarted)
      redirect_back_or_to household_record_path(Current.household, @record), notice: t(".restarted")
    else
      redirect_back_or_to household_record_path(Current.household, @record), alert: @record.errors.full_messages.to_sentence
    end
  end

  def create
    authorize Record
    @record = Current.household.records.new(created_by: Current.user)
    assign(@record)
    @continues = Current.household.records.find_by(id: params[:continues_id]) if params[:continues_id].present?
    if save_with_event(@record, :created) { @continues&.update!(next_due_on: nil) }
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
      # The sheet ID is never reused; a later import offers Skip / Re-create for it
      Current.household.import_keys.where(record_id: @record.id).update_all(status: "retired", retired_digest: @record.import_digest)
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
    @record = Current.household.records.with_attached_photos.find(params[:id])
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
      yield if block_given?
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end
