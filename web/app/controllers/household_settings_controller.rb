# Household settings (PRD §14): everyone sees them, only the owner changes them
class HouseholdSettingsController < ApplicationController
  include HouseholdScoped

  def show
    authorize Current.household
    @events = SecurityEvent.where(household_id: Current.household.id).order(created_at: :desc).limit(30)
  end

  def update
    authorize Current.household, :manage?
    if Current.household.update(params.expect(household: %i[name default_currency reminder_lead_days]))
      SecurityEvent.record!("household_updated", actor: Current.user, household: Current.household, changes: Current.household.saved_changes.except("updated_at").keys)
      redirect_to household_settings_path(Current.household), notice: t(".saved")
    else
      @events = SecurityEvent.where(household_id: Current.household.id).order(created_at: :desc).limit(30)
      render :show, status: :unprocessable_content
    end
  end
end
