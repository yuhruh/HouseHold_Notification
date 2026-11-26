module Spike
  # M0 spike pages. Protected by HTTP basic auth (SPIKE_USER / SPIKE_PASSWORD).
  # In production they are 404 unless both variables are set; removed after M5.
  class BaseController < ApplicationController
    # Wrong basic-auth guesses one IP may make per window (like the 10 per 3 minutes on sign-in)
    WRONG_GUESSES_PER_IP = 10
    GUESS_WINDOW = 3.minutes

    allow_unauthenticated_access
    before_action :require_spike_access

    private

    def require_spike_access
      user, password = ENV["SPIKE_USER"], ENV["SPIKE_PASSWORD"]
      if user.blank? || password.blank?
        head :not_found unless Rails.env.local?
        return
      end

      if ActionController::HttpAuthentication::Basic.has_basic_credentials?(request) && too_many_wrong_guesses?
        head :too_many_requests
        return
      end

      authenticate_or_request_with_http_basic("spike") do |u, p|
        correct = ActiveSupport::SecurityUtils.secure_compare(u, user) & ActiveSupport::SecurityUtils.secure_compare(p, password)
        cache_store.decrement(guess_key, 1, expires_in: GUESS_WINDOW) if correct
        correct
      end
    end

    # Counts the attempt before the password is checked, so parallel guesses can't all get in
    # under the limit; a correct one is taken back off above. If the cache can't count (nil),
    # the attempt is let through, as ActionController::RateLimiting does.
    def too_many_wrong_guesses?
      count = cache_store.increment(guess_key, 1, expires_in: GUESS_WINDOW)
      count.present? && count > WRONG_GUESSES_PER_IP
    end

    def guess_key = "rate-limit:spike-basic-auth:#{request.remote_ip}"
  end
end
