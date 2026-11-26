# Records CRUD; Edit Details changes only the bill, Record Payment only the payment, filled in (PRD §1, §2). Every write goes through save! and logs a
# record_events row in the same transaction.
class RecordsController < ApplicationController
  include HouseholdScoped
  include InlinePaymentMethod
  before_action :set_record, except: %i[index new create]
  helper_method :form_mode
  PAST_SHOWN = 5

  def index
    authorize Record
    @filter = Records::Filter.new(Current.household, params.permit(*Records::Filter::KEYS))
    @filter.paginate(page: params[:page], per: per_page)
    @to_pay = Records::ToPay.new(Current.household)
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
    # Past Records: earlier billing periods of the same item (same category and details), newest first
    past = Current.household.records.where(category_id: @record.category_id, details: @record.details).where.not(id: @record.id)
      .where("period_year * 12 + period_start_month < ?", @record.period_year * 12 + @record.period_start_month)
    @past_count = past.count
    @past = past.order(period_year: :desc, period_start_month: :desc, id: :desc).limit(PAST_SHOWN)
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
    # A recurring bill's next one is made by its template, not by Done
    return redirect_to household_record_path(Current.household, @record) if @record.recurring_template_id
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
    @new_payment_method = inline_payment_method(:record)
    @continues = Current.household.records.find_by(id: params[:continues_id]) if params[:continues_id].present?
    if !inline_payment_method_invalid?(@new_payment_method, @record) &&
        save_with_event(@record, :created, payment_method: @new_payment_method) { @continues&.update!(next_due_on: nil) }
      notice = inline_payment_method_notice(t(".created"), @new_payment_method)
      # "Save and Make Recurring": on to New recurring bill, filled in from this record
      if params[:make_recurring].present? && policy(RecurringTemplate).new?
        redirect_to new_household_recurring_template_path(Current.household, from_record: @record.id), notice:
      else
        redirect_to household_record_path(Current.household, @record), notice:
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @record
    prefill_payment if form_mode == :pay
  end

  def update
    authorize @record
    mode = form_mode # before saving: once the bill is paid it no longer counts as paying
    paid_in_full = @record.amount_paid.present? && @record.amount_paid == @record.amount_required
    assign(@record)
    @new_payment_method = inline_payment_method(:record)
    if mode == :details
      # Edit Details on a bill paid in full: the payment follows a corrected amount due, as Paid in full does
      @record.amount_paid = @record.amount_required if paid_in_full && !@record.maintenance? && @record.amount_required.present? && @record.amount_required_changed?
    elsif @record.maintenance? && (mode == :pay || @record.paid_on)
      # Maintenance done: the cost entered is what it cost (blank = nothing), not a part payment
      @record.amount_required = @record.amount_paid
    end
    paying = mode == :pay
    if !inline_payment_method_invalid?(@new_payment_method, @record) &&
        save_with_event(@record, paying ? :marked_paid : :updated, payment_method: @new_payment_method)
      notice =
        if !paying then t(".saved")
        elsif @record.maintenance? then t(".done", title: @record.title)
        else t(".paid", title: @record.title)
        end
      redirect_to household_record_path(Current.household, @record), notice: inline_payment_method_notice(notice, @new_payment_method)
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
      Reminders::Inbox.forget!(@record)
      @record.destroy!
    end
    redirect_to household_records_path(Current.household), notice: t(".deleted")
  end

  # GET asks for the bill amount when Required is blank (not needed for Maintenance)
  private

  # Rows per page: 10 / 20 / 50 or a custom number, remembered on this device
  def per_page
    per = (params[:per] == "custom" ? params[:per_custom] : params[:per]).to_i
    return cookies.permanent[:records_per] = per if per.between?(1, Records::Filter::MAX_PER_PAGE)

    cookies[:records_per]
  end

  def set_record
    @record = Current.household.records.with_attached_photos.find(params[:id])
  end

  def assign(record)
    record.assign_attributes(params.expect(record: %i[category_id title details period_year period_start_month period_end_month
      currency amount_required amount_paid payable_from due_on paid_on payment_method_id payment_note next_due_on reminder_frequency
      reminder_starts_on bill_number lock_version]))
    # Another household's category is only rejected by validation; its type isn't read either
    category = record.category if record.category&.household_id == Current.household.id
    record.record_type = category&.record_type
  end

  # Which part of the record the edit form shows: Record Payment (`pay` on a bill that isn't paid yet, filled
  # in), Edit Payment (`payment`, or `pay` on a paid one) or Edit Details (the bill itself)
  def form_mode
    @form_mode ||= if params[:pay].present? && !@record.settled then :pay
    elsif params[:pay].present? || params[:payment].present? then :edit_payment
    else :details
    end
  end

  # Paid in full (maintenance: done, at its expected cost), today, with the payment method last used for
  # this category; nothing is saved until Save
  def prefill_payment
    @record.amount_paid = @record.amount_required if @record.amount_required
    @record.paid_on = Date.current
    @record.payment_method_id ||= helpers.last_payment_methods[@record.category_id.to_s]
  end

  # `payment_method`: one chosen or typed in with "+ New payment method…", added in the same transaction
  def save_with_event(record, action, payment_method: nil)
    Record.transaction do
      if payment_method
        payment_method.save! if payment_method.new_record?
        record.payment_method = payment_method
      end
      record.save!
      RecordEvent.log!(record, action, user: Current.user)
      yield if block_given?
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end
end
