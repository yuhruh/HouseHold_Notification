class ApplicationController < ActionController::Base
  include Authentication
  include Localization
  include Pundit::Authorization
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from Pundit::NotAuthorizedError do
    head :forbidden
  end

  private
    def pundit_user = Current.membership
end
