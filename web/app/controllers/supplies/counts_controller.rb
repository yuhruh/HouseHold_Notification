# −1 Used one and "I have N left". From the list or the item page the row and Forecast card update
# in place (Turbo Stream) with a toast that can Undo; Undo deletes that count. With several brands in
# stock, −1 comes with the brand picked (`product`) and the count with a number for each brand
# (`supply_count[brands]`); the item's count is still one number (Supplies::Brands). On the item
# page a brand restocked before it ran out has a −1 per batch (`batch`: the purchase's id).
class Supplies::CountsController < ApplicationController
  include HouseholdScoped
  before_action :set_supply

  def create
    authorize @supply, :update?
    @count = if params[:used_one].present? then used_one
    elsif params.dig(:supply_count, :brands).present? then counted_by_brand
    else Supplies::RecordCount.call(@supply, count_level, user: Current.user)
    end
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

  # −1 of the brand (or the batch) picked. A brand or batch with none left any more (the page was
  # old) is refused, not taken from another one
  def used_one
    return used_one_of_batch if params.key?(:batch)
    return Supplies::RecordCount.used_one(@supply, user: Current.user) unless params.key?(:product)

    @brand = @supply.brands.find(params[:product])
    return @supply.counts.new.tap { it.errors.add(:base, t("supplies.brands.gone")) } unless @brand
    Supplies::RecordCount.used_one(@supply, user: Current.user, product: @brand.key)
  end

  # One batch: a purchase, or the stock with no purchase behind it (Supplies::Brands::NO_PURCHASE)
  def used_one_of_batch
    @batch = @supply.brands.find_batch(params[:batch])
    return @supply.counts.new.tap { it.errors.add(:base, t("supplies.brands.batch_gone")) } unless @batch
    Supplies::RecordCount.used_one(@supply, user: Current.user, product: @batch.product, purchase: @batch.purchase, no_purchase: @batch.purchase.nil?)
  end

  # "I have N left", one number per brand this item was bought as; the count is their sum
  def counted_by_brand
    known = @supply.brands.keys
    rows = Array(params.dig(:supply_count, :brands)).filter_map { it.permit(:name, :left).to_h if it.respond_to?(:permit) }
    rows = rows.select { known.include?(it[:name].to_s) }
    numbers = rows.to_h { [ it[:name].to_s, whole(it[:left]) ] }
    wrong = numbers.values.find { !it.is_a?(Integer) }
    return Supplies::RecordCount.call(@supply, wrong, user: Current.user) if wrong || numbers.empty?
    Supplies::RecordCount.by_brand(@supply, numbers, user: Current.user)
  end

  # Whole numbers from 0 up only: "2.5" or "-1" is refused, not rounded
  def count_level = whole(params.dig(:supply_count, :level))

  def whole(raw)
    raw = raw.to_s.strip
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
    when :used_one
      if @batch then t("supplies.toast.used_one_batch", batch: helpers.supply_expiry(@batch.expires_on), left:)
      elsif @brand&.named? then t("supplies.toast.used_one_product", product: @brand.name, left:)
      else t("supplies.toast.used_one", left:)
      end
    when :counted then t("supplies.toast.counted", left:)
    else t("supplies.toast.undone", left:)
    end
  end
end
