module Spike
  # VAPID keys come from Rails credentials (vapid.public_key / vapid.private_key) or ENV.
  # They must never be rotated casually: every subscription is bound to the public key.
  module Vapid
    def self.public_key
      ENV["VAPID_PUBLIC_KEY"].presence || Rails.application.credentials.dig(:vapid, :public_key)
    end

    def self.private_key
      ENV["VAPID_PRIVATE_KEY"].presence || Rails.application.credentials.dig(:vapid, :private_key)
    end

    def self.subject
      ENV["VAPID_SUBJECT"].presence || "mailto:#{Rails.application.credentials.dig(:gmail, :sender) || 'admin@example.com'}"
    end
  end
end
