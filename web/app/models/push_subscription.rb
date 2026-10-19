# A browser subscribed to Web Push for one user (PRD §16)
class PushSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :session, optional: true

  validates :endpoint, :p256dh, :auth, presence: true

  # Upsert by endpoint and reassign to whoever is signed in on that browser now
  def self.subscribe!(user:, session:, params:, user_agent:)
    find_or_initialize_by(endpoint: params.fetch(:endpoint)).tap do |sub|
      sub.update!(user:, session:, p256dh: params.dig(:keys, :p256dh), auth: params.dig(:keys, :auth),
        user_agent: user_agent.to_s.first(500), device_label: label_for(user_agent))
    end
  end

  def self.label_for(user_agent)
    ua = user_agent.to_s
    os = if ua.include?("Android") then "Android"
    elsif ua.match?(/iPhone|iPad/) then "iOS"
    elsif ua.include?("Mac OS") then "Mac"
    elsif ua.include?("Windows") then "Windows"
    else "Linux"
    end
    browser = if ua.include?("Edg/") then "Edge" elsif ua.include?("Firefox") then "Firefox" elsif ua.include?("Chrome") then "Chrome" else "Browser" end
    "#{os} · #{browser}"
  end
end
