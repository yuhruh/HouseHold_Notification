module Spike
  # M0 spike pages. Protected by HTTP basic auth (SPIKE_USER / SPIKE_PASSWORD).
  # In production they are 404 unless both variables are set; removed after M5.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    before_action :require_spike_access

    private

    def require_spike_access
      user, password = ENV["SPIKE_USER"], ENV["SPIKE_PASSWORD"]
      if user.blank? || password.blank?
        head :not_found unless Rails.env.local?
        return
      end

      authenticate_or_request_with_http_basic("spike") do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u, user) & ActiveSupport::SecurityUtils.secure_compare(p, password)
      end
    end
  end
end
