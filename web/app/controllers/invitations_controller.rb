# The signed-in user's pending invitations, matched by verified email (PRD §12a). Accepting is always
# an explicit choice; authorization is the email match, never the link token.
class InvitationsController < ApplicationController
  def index
    @invitations = Invitation.pending_for(Current.user).includes(:household, :invited_by).order(:created_at)
  end

  def accept
    invitation = Invitation.pending_for(Current.user).find(params[:id])
    invitation.accept!(Current.user)
    Current.user.update!(last_household: invitation.household)
    redirect_to household_path(invitation.household), notice: t(".accepted", household: invitation.household.name)
  end

  def decline
    Invitation.pending_for(Current.user).find(params[:id]).decline!(Current.user)
    redirect_to root_path, notice: t(".declined")
  end
end
