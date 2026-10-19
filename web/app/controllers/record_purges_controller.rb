# Settings → Danger zone → Delete all records (owner only), confirmed by typing the household name
class RecordPurgesController < ApplicationController
  include HouseholdScoped
  include Reauthentication
  before_action { authorize Current.household, :manage? }
  before_action -> { require_reauthentication("delete_records") }, only: :new
  before_action -> { require_reauthentication("delete_records", return_to: new_household_record_purge_path(Current.household)) }, only: :create

  def new
    @count = Current.household.records.count
    @templates = Current.household.recurring_templates.count
  end

  def create
    return redirect_to(new_household_record_purge_path(Current.household), alert: t("household_deletions.create.name_mismatch")) unless params[:confirm_name].to_s.strip == Current.household.name

    count = Records::PurgeAll.call(Current.household, actor: Current.user, delete_templates: params[:delete_templates] == "1",
      today: Time.use_zone(Current.user.time_zone) { Date.current })
    redirect_to household_records_path(Current.household), notice: t(".deleted", count:)
  end
end
