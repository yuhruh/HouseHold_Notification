# Personal snooze on one record, all channels (PRD §6). Viewers can snooze too.
class SnoozesController < ApplicationController
  include HouseholdScoped
  before_action :set_record

  def create
    authorize @record, :show?
    until_on = params[:until_on].present? ? Date.iso8601(params[:until_on]) : Date.current + params.require(:days).to_i
    if until_on <= Date.current || until_on > Date.current + ReminderSnooze::MAX_DAYS
      return redirect_back_or_to household_record_path(Current.household, @record), alert: t(".invalid", max: ReminderSnooze::MAX_DAYS)
    end

    ReminderSnooze.find_or_initialize_by(record: @record, user: Current.user).update!(until_on:)
    redirect_back_or_to household_record_path(Current.household, @record), notice: t(".snoozed", date: l(until_on))
  rescue Date::Error
    redirect_back_or_to household_record_path(Current.household, @record), alert: t(".invalid", max: ReminderSnooze::MAX_DAYS)
  end

  def destroy
    authorize @record, :show?
    ReminderSnooze.where(record: @record, user: Current.user).delete_all
    redirect_back_or_to household_record_path(Current.household, @record), notice: t(".cancelled")
  end

  private

  def set_record
    @record = Current.household.records.find(params[:id])
  end
end
