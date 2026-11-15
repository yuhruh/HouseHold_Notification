# Sent to an email the owner adds under Electricity › Other Emails That Forward: this ledger's
# forwarding address and how to set up Gmail to send 台電's emails there.
class ElectricityForwardingMailer < ApplicationMailer
  def setup
    @account = params[:account]
    @address = @account.inbox_address
    @owner = params[:added_by]&.display_name.presence || params[:added_by]&.email_address || "Household Tracker"
    mail to: params[:email], subject: t(".subject", household: @account.household.name)
  end
end
