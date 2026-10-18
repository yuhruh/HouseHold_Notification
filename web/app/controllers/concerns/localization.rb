# Wraps each request in the user's locale and time zone (PRD §11, §17). Signed-out visitors get the
# browser's language if supported, else zh-TW, and Asia/Taipei.
module Localization
  extend ActiveSupport::Concern

  included do
    around_action :use_locale_and_time_zone
  end

  private
    def use_locale_and_time_zone(&)
      user = Current.user || (resume_session && Current.user)
      I18n.with_locale(user&.locale.presence || browser_locale || I18n.default_locale) do
        Time.use_zone(user&.time_zone || User::DEFAULT_TIME_ZONE, &)
      end
    end

    def browser_locale
      request.accept_language.to_s.split(",").each do |entry|
        tag = entry.split(";").first.to_s.strip.downcase
        return :"zh-TW" if tag.start_with?("zh")
        return :en if tag.start_with?("en")
      end
      nil
    end
end
