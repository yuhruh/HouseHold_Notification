# /forward/:token, linked from the setup email (ForwardingSetupMailer): the ledger's
# forwarding address with a Copy button, because an email can't hold a working Copy button. No
# sign-in: the token is already part of the address itself, and the page shows nothing else.
class ForwardingAddressesController < ApplicationController
  allow_unauthenticated_access

  def show
    @inbox = ForwardingInbox.includes(:household).find_by(inbox_token: params[:token])
    @address = @inbox&.address
    render :missing, status: :not_found unless @address
  end
end
