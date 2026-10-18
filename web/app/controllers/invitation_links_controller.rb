# /invitations/:token from the email only routes the visitor (PRD §12a)
class InvitationLinksController < ApplicationController
  allow_unauthenticated_access

  def show
    @invitation = Invitation.find_by_token(params[:token])
    return render(:invalid, status: :not_found) unless @invitation&.pending?

    if !authenticated?
      session[:return_to_after_authenticating] = request.url
      @email = @invitation.email
      render :signed_out
    elsif @invitation.acceptable_by?(Current.user)
      redirect_to invitations_path
    else
      render :wrong_account
    end
  end
end
