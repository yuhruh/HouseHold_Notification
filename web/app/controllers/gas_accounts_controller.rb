# Ledger settings › Gas account (owner only): the ledger's 欣桃天然氣 用戶編號, the category its bills
# go in, and Check now. Saving a new number checks it at once.
class GasAccountsController < ApplicationController
  include HouseholdScoped
  rate_limit to: 6, within: 1.minute, only: :check, by: -> { Current.household.id },
    with: -> { redirect_to household_gas_account_path(Current.household), alert: t("auth.rate_limited") }
  before_action { authorize GasAccount, :manage? }
  before_action :set_gas_account

  def show
  end

  def update
    @gas_account.assign_attributes(params.expect(gas_account: %i[customer_code category_id payment_method_id enabled]))
    check = @gas_account.new_record? || @gas_account.customer_code_changed?
    if @gas_account.save
      Utilities::ShintaoGas::Sync.call(@gas_account) if check && @gas_account.enabled
      redirect_to household_gas_account_path(Current.household), notice: t(".saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  def check
    return redirect_to(household_gas_account_path(Current.household)) if @gas_account.new_record?

    lines = Utilities::ShintaoGas::Sync.call(@gas_account)
    notice = lines && t(".done", count: lines.size)
    redirect_to household_gas_account_path(Current.household), notice:, alert: (t(".failed") unless lines)
  end

  # Disconnect: bills it added stay, as bills
  def destroy
    @gas_account.destroy! if @gas_account.persisted?
    redirect_to household_gas_account_path(Current.household), notice: t(".disconnected")
  end

  private

  def set_gas_account
    @gas_account = Current.household.gas_account ||
      Current.household.build_gas_account(category: Current.household.categories.active.where(record_type: "expense").find_by(name_zh: "瓦斯費"))
  end
end
