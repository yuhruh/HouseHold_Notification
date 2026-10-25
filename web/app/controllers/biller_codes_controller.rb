# Remembers what a bill's biller code means for this household (asked once, from the bill scan)
class BillerCodesController < ApplicationController
  include HouseholdScoped

  def create
    authorize Record, :create?
    code = Current.household.biller_codes.find_or_initialize_by(code: params[:code].to_s.upcase)
    code.assign_attributes(category: Current.household.categories.find_by(id: params[:category_id]), deadline_offset_days: params[:deadline_offset_days].to_i)
    if code.save
      head :no_content
    else
      render json: { errors: code.errors.full_messages }, status: :unprocessable_content
    end
  end
end
