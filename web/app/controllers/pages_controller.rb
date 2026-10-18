# Public pages: home and privacy policy (linked from the Google OAuth consent screens).
class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
  end

  def privacy
  end
end
