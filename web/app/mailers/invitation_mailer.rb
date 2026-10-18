class InvitationMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    @url = invitation_link_url(params[:token])
    mail to: @invitation.email, subject: t(".subject", household: @invitation.household.name)
  end
end
