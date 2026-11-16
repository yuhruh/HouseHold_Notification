# Edit › Barcodes: take a saved barcode off an item (one linked by mistake, or a duplicate item's
# before it is archived). The next scan of that code is then treated as new.
class Supplies::BarcodesController < ApplicationController
  include HouseholdScoped

  def destroy
    supply = Current.household.supplies.find(params[:supply_id])
    authorize supply, :update?
    barcode = supply.barcodes.find(params[:id])
    barcode.destroy!
    redirect_to household_supply_path(Current.household, supply), notice: t(".removed", code: barcode.code, item: supply.name), status: :see_other
  end
end
