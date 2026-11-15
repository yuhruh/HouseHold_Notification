# New → Scan barcode or receipt. The camera or photo is read in the browser (supply_scan_controller);
# only the barcode number comes here. A barcode the household saved goes straight to that item's
# Bought form; one a product database knows opens New item filled in; anything else opens it empty
# with the barcode attached.
class Supplies::ScansController < ApplicationController
  include HouseholdScoped

  def show
    authorize Supply, :create?
    @mode = params[:mode] == "receipt" ? "receipt" : "barcode"
  end

  def barcode
    authorize Supply, :create?
    code = params[:code].to_s.gsub(/\D/, "")
    unless Supplies::BarcodeLookup.valid?(code)
      return redirect_to scan_household_supplies_path(Current.household), alert: t(".invalid"), status: :see_other
    end

    result = Supplies::BarcodeLookup.call(Current.household, code)
    if result.known?
      redirect_to new_household_supply_purchase_path(Current.household, result.supply, scan: 1), notice: t(".known", item: result.supply.name), status: :see_other
    elsif result.found?
      filled = [ "name", ("kind" if result.kind) ].compact
      redirect_to new_household_supply_path(Current.household, name: result.name, kind: result.kind, barcode: code, source: result.source,
                                            original_name: result.original_name, brand: result.brand, filled:), status: :see_other
    else
      redirect_to new_household_supply_path(Current.household, barcode: code, not_found: 1), status: :see_other
    end
  end
end
