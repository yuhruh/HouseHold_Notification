class MembersController < ApplicationController
  include HouseholdScoped

  def index
    authorize Current.household, :show?
    @memberships = Current.household.memberships.includes(user: [ :push_subscriptions, { avatar_attachment: :blob } ]).order(:created_at)
    @invitations = Current.household.invitations.pending.order(:created_at) if policy(Current.household).manage_members?
    @invitation = Current.household.invitations.new(role: "viewer")
  end
end
