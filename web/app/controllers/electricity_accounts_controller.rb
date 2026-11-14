# Ledger settings › Electricity (台電): the forwarding address for 台電's emails, the category their
# bills go in, and (optionally) the 電號. Saving the first time creates the address.
class ElectricityAccountsController < ApplicationController
  include HouseholdScoped
  before_action :set_electricity_account
  before_action { authorize @electricity_account }

  def show
  end

  def update
    attributes = params.expect(electricity_account: [ :customer_code, :category_id, :payment_method_id, :allowed_senders ])
    # One email per line (or comma) in the form; the column is an array
    attributes[:allowed_senders] = attributes[:allowed_senders].to_s.split(/[\s,]+/) if attributes.key?(:allowed_senders)
    @electricity_account.assign_attributes(attributes)
    if @electricity_account.save
      redirect_to household_electricity_account_path(Current.household), notice: t(".saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  # Disconnect: the address stops working; bills it added stay, as bills
  def destroy
    @electricity_account.destroy! if @electricity_account.persisted?
    redirect_to household_electricity_account_path(Current.household), notice: t(".disconnected")
  end

  private

  def set_electricity_account
    @electricity_account = Current.household.electricity_account ||
      Current.household.build_electricity_account(category: Current.household.categories.active.where(record_type: "expense").find_by(name_zh: "電費"))
  end
end
