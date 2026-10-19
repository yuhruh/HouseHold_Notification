# VAPID keys come from Rails credentials (vapid.public_key / vapid.private_key) or ENV. Never rotate
# them casually: every push subscription is bound to the public key (docs/NOTIFICATIONS.md).
module Vapid
  def self.public_key = ENV["VAPID_PUBLIC_KEY"].presence || Rails.application.credentials.dig(:vapid, :public_key)
  def self.private_key = ENV["VAPID_PRIVATE_KEY"].presence || Rails.application.credentials.dig(:vapid, :private_key)

  def self.subject
    ENV["VAPID_SUBJECT"].presence || "mailto:#{Rails.application.credentials.dig(:gmail, :sender) || 'admin@example.com'}"
  end

  def self.options = { subject:, public_key:, private_key: }
end
