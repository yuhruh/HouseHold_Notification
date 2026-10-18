# Zero memberships: create a household, or wait for an invite (PRD §12a). Sign-up never creates one.
class OnboardingsController < ApplicationController
  def show
    @household = Household.new
  end
end
