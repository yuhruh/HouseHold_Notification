# Bills › To Pay (PRD §6): the bills still to pay, most urgent first (Records::ToPay)
class PendingController < ApplicationController
  include HouseholdScoped

  def show
    authorize Record, :show?
    @to_pay = Records::ToPay.new(Current.household)
    @today = @to_pay.today
    @snoozes = ReminderSnooze.where(user: Current.user, record_id: Current.household.records.select(:id)).pluck(:record_id, :until_on).to_h
  end
end
