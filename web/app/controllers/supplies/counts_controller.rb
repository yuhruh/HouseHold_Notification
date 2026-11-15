# −1 Used one and "I have N left". From the list or the item page the row and Forecast card update
# in place (Turbo Stream) with a toast that can Undo; Undo deletes that count.
class Supplies::CountsController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def create
    authorize @supply, :update?
    @count = params[:used_one].present? ? Supplies::RecordCount.used_one(@supply, user: Current.user) : Supplies::RecordCount.call(@supply, count_level, user: Current.user)
    return respond_invalid unless @count.persisted?

    @supply.reload
    @forecast = @supply.forecast
    @toast = params[:used_one].present? ? :used_one : :counted
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to household_supply_path(Current.household, @supply), notice: toast_text, status: :see_other }
    end
  end

  def destroy
    authorize @supply, :update?
    Supplies::RecordCount.undo(@supply.counts.find(params[:id]))
    @supply.reload
    @forecast = @supply.forecast
    @toast = :undone
    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to household_supply_path(Current.household, @supply), notice: toast_text, status: :see_other }
    end
  end

  helper_method :toast_text

  private

  def set_supply
    @supply = Current.household.supplies.active.includes(:purchases, :counts).find(params[:supply_id])
  end

  # Whole numbers from 0 up only: "2.5" or "-1" is refused, not rounded
  def count_level
    raw = params.dig(:supply_count, :level).to_s.strip
    raw.match?(/\A\d+\z/) ? raw.to_i : raw
  end

  def respond_invalid
    message = @count.errors.full_messages.to_sentence
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.update("supply_toast", partial: "supplies/toast", locals: { text: message, count: nil, error: true }), status: :unprocessable_content }
      format.html { redirect_to household_supply_path(Current.household, @supply), alert: message, status: :see_other }
    end
  end

  def toast_text
    left = helpers.supply_left(@supply, @forecast)
    case @toast
    when :used_one then t("supplies.toast.used_one", left:)
    when :counted then t("supplies.toast.counted", left:)
    else t("supplies.toast.undone", left:)
    end
  end
end
