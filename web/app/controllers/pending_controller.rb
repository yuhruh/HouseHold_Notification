# Pending / Overdue (PRD §6), in the viewer's local today
class PendingController < ApplicationController
  include HouseholdScoped
  HORIZON = 30

  def show
    authorize Record, :show?
    @today = Date.current
    unpaid = Current.household.records.where(settled: false).includes(:category)
    @overdue = unpaid.where(due_on: ...@today).order(:due_on)
    @soon = unpaid.where(due_on: @today..(@today + HORIZON)).order(:due_on)
    @maintenance = Current.household.records.where(next_due_on: ..(@today + HORIZON)).includes(:category).order(:next_due_on)
    @no_due = unpaid.where(due_on: nil).order(:period_year, :period_start_month)
    # Unpaid bills due after the 30 days, so nothing unpaid is missing from the page
    @later = unpaid.where(due_on: (@today + HORIZON + 1)..).order(:due_on)
    @snoozes = ReminderSnooze.where(user: Current.user, record_id: Current.household.records.select(:id)).pluck(:record_id, :until_on).to_h
  end
end
