# Header language switch (PRD §11): signed in, it saves users.locale (the same setting as My account);
# signed out, it keeps the choice in a cookie. Goes back to the page it came from.
class LocalesController < ApplicationController
  allow_unauthenticated_access

  def update
    locale = params[:locale].to_s
    if I18n.available_locales.map(&:to_s).include?(locale)
      if authenticated?
        Current.user.update!(locale:)
      else
        cookies.permanent[:locale] = locale
      end
    end
    redirect_back_or_to root_path
  end
end
