class HouseholdsController < ApplicationController
  include HouseholdScoped
  skip_before_action :set_household, only: :create
  skip_after_action :verify_authorized, only: :create

  def show
    authorize Current.household
    @to_pay = Records::ToPay.new(Current.household)
    @paid = Current.household.records.where(settled: true).where.not(paid_on: nil).order(paid_on: :desc, id: :desc).limit(3).includes(:category)
  end

  def create
    @household = Households::Create.call(user: Current.user, params: params.expect(household: %i[name default_currency]))
    if @household.persisted?
      redirect_to household_path(@household), notice: t(".created")
    else
      render "onboardings/show", status: :unprocessable_content
    end
  end
end
