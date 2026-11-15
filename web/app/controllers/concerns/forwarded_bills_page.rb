# Ledger settings › Electricity and › Water: the page of a utility whose bills come by forwarded
# email (ForwardedBills). Shows the status, the shared "Set up forwarding" steps (their actions are
# ForwardingInboxesController's) and the bill settings; saving the first time turns it on and
# creates the ledger's forwarding address. Only the owner changes anything.
#
# The including controller defines `account_class` and `default_category_name`.
module ForwardedBillsPage
  extend ActiveSupport::Concern

  included do
    include HouseholdScoped
    before_action :set_account
    before_action { authorize @account }
  end

  def show
    render "utility_accounts/forwarded_bills"
  end

  def update
    @account.assign_attributes(params.expect(account_class.model_name.param_key => %i[customer_code category_id payment_method_id]))
    if @account.save
      redirect_to page_path, notice: t(".saved")
    else
      render "utility_accounts/forwarded_bills", status: :unprocessable_content
    end
  end

  # Disconnect: bills it added stay, as bills. The forwarding address stops working once neither
  # Electricity nor Water uses it.
  def destroy
    @account.destroy! if @account.persisted?
    redirect_to page_path, notice: t(".disconnected")
  end

  private

  def association = account_class.model_name.singular

  def set_account
    category = Current.household.categories.active.where(record_type: "expense").find_by(name_zh: default_category_name)
    @account = Current.household.public_send(association) || Current.household.public_send("build_#{association}", category:)
  end

  def page_path = public_send("household_#{association}_path", Current.household)
end
