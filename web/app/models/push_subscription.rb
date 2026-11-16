# A browser subscribed to Web Push for one user (PRD §16)
class PushSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :session, optional: true

  # The push services browsers subscribe to: Chrome, Edge, Brave, Opera and Samsung Internet (Google),
  # Firefox (Mozilla), Safari (Apple) and older Edge (Windows). The app's server posts to the
  # endpoint a browser hands in, so it has to be one of these, over HTTPS on the usual port, and
  # never an address of someone's choosing.
  PUSH_HOSTS = /\A(?:fcm\.googleapis\.com|android\.googleapis\.com|(?:[a-z0-9-]+\.)+push\.services\.mozilla\.com|
    (?:[a-z0-9-]+\.)+push\.apple\.com|(?:[a-z0-9-]+\.)+notify\.windows\.com)\z/x
  # Browsers a member can have subscribed at once; a new one past this replaces the one unused longest
  MAX_PER_USER = 20

  validates :endpoint, :p256dh, :auth, presence: true
  validate(if: :will_save_change_to_endpoint?) { errors.add(:endpoint, :invalid) unless self.class.push_service?(endpoint) }

  def self.push_service?(endpoint)
    uri = URI.parse(endpoint.to_s)
    uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && uri.host.to_s.downcase.match?(PUSH_HOSTS)
  rescue URI::InvalidURIError
    false
  end

  # Upsert by endpoint and reassign to whoever is signed in on that browser now
  def self.subscribe!(user:, session:, params:, user_agent:)
    find_or_initialize_by(endpoint: params.fetch(:endpoint)).tap do |sub|
      sub.update!(user:, session:, p256dh: params.dig(:keys, :p256dh), auth: params.dig(:keys, :auth),
        user_agent: user_agent.to_s.first(500), device_label: label_for(user_agent))
      user.push_subscriptions.where.not(id: sub.id).order(updated_at: :desc, id: :desc).offset(MAX_PER_USER - 1).destroy_all
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
