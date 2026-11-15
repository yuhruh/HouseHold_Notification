# Ledger settings › Electricity (台電): set up forwarding (who forwards 台電's emails, the setup
# email, Gmail's confirmation), the bill settings, and what came in. Saving the first time creates
# the forwarding address. Only the owner changes anything or sends the setup email.
class ElectricityAccountsController < ApplicationController
  include HouseholdScoped
  before_action :set_electricity_account
  before_action { authorize @electricity_account }
  before_action :require_turned_on, only: %i[setup_email add_forwarder remove_forwarder]

  def show
  end

  def update
    @electricity_account.assign_attributes(params.expect(electricity_account: %i[customer_code category_id payment_method_id]))
    if @electricity_account.save
      redirect_to household_electricity_account_path(Current.household), notice: t(".saved")
    else
      render :show, status: :unprocessable_content
    end
  end

  # Send (or resend) the setup email to one of the forwarders
  def setup_email
    email = submitted_email
    return back(alert: t(".unknown")) unless @electricity_account.forwarder?(email)
    return back(alert: t(".too_soon", email:)) if @electricity_account.setup_sent_recently?(email)

    send_setup(email)
    back(notice: t(".sent", email:))
  end

  # Add an email that forwards, and send it the setup email
  def add_forwarder
    email = submitted_email
    return back(alert: t(".already", email:)) if @electricity_account.forwarder?(email)

    @electricity_account.allowed_senders += [ email ]
    return render(:show, status: :unprocessable_content) unless @electricity_account.save

    send_setup(email)
    back(notice: t(".added", email:))
  end

  # Members are always allowed; only an added email is removed
  def remove_forwarder
    email = submitted_email
    if @electricity_account.allowed_senders.include?(email)
      @electricity_account.update!(allowed_senders: @electricity_account.allowed_senders - [ email ],
        setup_emails_sent: @electricity_account.setup_emails_sent.except(email))
    end
    back(notice: t(".removed", email:))
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

  def require_turned_on
    back unless @electricity_account.persisted? && @electricity_account.inbox_address
  end

  def submitted_email = params.expect(:email).to_s.strip.downcase

  def send_setup(email)
    ElectricityForwardingMailer.with(account: @electricity_account, email:, added_by: Current.user, locale: I18n.locale.to_s).setup.deliver_later
    @electricity_account.setup_sent!(email)
  end

  def back(**flash) = redirect_to(household_electricity_account_path(Current.household, anchor: "electricity-setup"), **flash)
end
