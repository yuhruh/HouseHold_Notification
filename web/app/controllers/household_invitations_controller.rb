# Owner-only invitation management on the members page (PRD §12, §14)
class HouseholdInvitationsController < ApplicationController
  include HouseholdScoped
  before_action { authorize Current.household, :manage_members? }
  rate_limit to: 20, within: 1.hour, only: %i[create resend], by: -> { Current.user.id }, with: -> { redirect_to household_members_path(Current.household), alert: t("auth.rate_limited") }

  def create
    params_in = params.expect(invitation: %i[email role expiry custom_date])
    email = params_in[:email].to_s.strip.downcase
    return redirect_to(household_members_path(Current.household), alert: t(".already_member")) if Current.household.users.exists?(email_address: email)

    invitation = Invitation.issue!(household: Current.household, invited_by: Current.user, email:, role: params_in[:role],
      expires_at: Invitation.expiry_from(params_in[:expiry], params_in[:custom_date]))
    deliver(invitation)
    redirect_to household_members_path(Current.household), notice: t(".sent", email: invitation.email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to household_members_path(Current.household), alert: e.record.errors.full_messages.to_sentence
  end

  # A fresh token and expiry; the old link stops working
  def resend
    old = Current.household.invitations.pending.find(params[:id])
    invitation = Invitation.issue!(household: Current.household, invited_by: Current.user, email: old.email, role: old.role,
      expires_at: Invitation.expiry_from(params[:expiry], params[:custom_date]))
    deliver(invitation)
    redirect_to household_members_path(Current.household), notice: t(".sent", email: invitation.email)
  end

  def revoke
    Current.household.invitations.open.find(params[:id]).revoke!
    redirect_to household_members_path(Current.household), notice: t(".revoked")
  end

  private
    def deliver(invitation)
      InvitationMailer.with(invitation:, token: invitation.token, locale: I18n.locale.to_s).invite.deliver_later
    end
end
