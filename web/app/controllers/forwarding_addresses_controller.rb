# /forward/:token, linked from the setup email (ElectricityForwardingMailer): the ledger's
# forwarding address with a Copy button, because an email can't hold a working Copy button. No
# sign-in: the token is already part of the address itself, and the page shows nothing else.
class ForwardingAddressesController < ApplicationController
  allow_unauthenticated_access

  def show
    @account = ElectricityAccount.includes(:household).find_by(inbox_token: params[:token])
    @address = @account&.inbox_address
    render :missing, status: :not_found unless @address
  end
end
