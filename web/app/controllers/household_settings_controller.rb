# Household settings (PRD §14): everyone sees them, only the owner changes them
class HouseholdSettingsController < ApplicationController
  include HouseholdScoped

  def show
    authorize Current.household
    load_events
  end

  def update
    authorize Current.household, :manage?
    if Current.household.update(params.expect(household: %i[name default_currency reminder_lead_days]))
      SecurityEvent.record!("household_updated", actor: Current.user, household: Current.household, changes: Current.household.saved_changes.except("updated_at").keys)
      redirect_to household_settings_path(Current.household), notice: t(".saved")
    else
      load_events
      render :show, status: :unprocessable_content
    end
  end

  private
    def load_events
      @events = SecurityEvent.where(household_id: Current.household.id).order(created_at: :desc).limit(30).to_a
      @event_users = User.where(id: @events.flat_map { [ _1.actor_id, _1.user_id ] }.compact.uniq).index_by(&:id)
    end
end
