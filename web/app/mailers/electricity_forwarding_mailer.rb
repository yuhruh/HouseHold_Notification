# Sent to an email the owner adds under Electricity › Other Emails That Forward: this ledger's
# forwarding address (with a link to a page that copies it) and how to set up Gmail to send
# 台電's emails there.
class ElectricityForwardingMailer < ApplicationMailer
  def setup
    @account = params[:account]
    @address = @account.inbox_address
    @copy_url = forwarding_address_url(token: @account.inbox_token)
    @owner = params[:added_by]&.display_name.presence || params[:added_by]&.email_address || "Household Tracker"
    mail to: params[:email], subject: t(".subject", household: @account.household.name)
  end
end
