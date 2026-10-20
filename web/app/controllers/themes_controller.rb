# Header theme menu: light, dark or the device's setting, kept in a cookie on this device (the
# layout reads it into <html data-theme>). Goes back to the page it came from.
class ThemesController < ApplicationController
  allow_unauthenticated_access

  THEMES = %w[light dark system].freeze

  def update
    cookies.permanent[:theme] = params[:theme] if THEMES.include?(params[:theme])
    redirect_back_or_to root_path
  end
end
