# Public pages: home, privacy policy (linked from the Google OAuth consent screens) and the family
# onboarding guide and the features overview (text in the locale files).
class PagesController < ApplicationController
  allow_unauthenticated_access

  # Signed in: pending invitations first, then the last/first household, else onboarding (PRD §12a)
  def home
    return unless authenticated?

    if Invitation.pending_for(Current.user).exists?
      redirect_to invitations_path
    elsif household = Current.user.home_household
      redirect_to household_path(household)
    else
      redirect_to onboarding_path
    end
  end

  def privacy
  end

  def guide
  end

  def features
  end
end
