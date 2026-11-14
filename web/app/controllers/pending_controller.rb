# Bills › To Pay (PRD §6): the bills still to pay, most urgent first; Bills › Coming Up: what isn't due
# yet, recurring bills not created yet included (both from Records::ToPay)
class PendingController < ApplicationController
  include HouseholdScoped
  before_action :load_bills

  def show; end

  def coming_up; end

  private

  def load_bills
    authorize Record, :show?
    @to_pay = Records::ToPay.new(Current.household)
    @today = @to_pay.today
    @snoozes = ReminderSnooze.where(user: Current.user, record_id: Current.household.records.select(:id)).pluck(:record_id, :until_on).to_h
  end
end
