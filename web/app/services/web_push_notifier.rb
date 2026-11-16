# A plain push without receipts, for messages that aren't digests (the owner's failure summary).
# Dead subscriptions (404/410) are removed; other errors are ignored (in-app always has a copy).
module WebPushNotifier
  module_function

  def notify(user, title:, body:, url:)
    user.push_subscriptions.find_each do |subscription|
      Push::Device.post(subscription, { title:, body:, url: }.to_json, urgency: "high")
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, Push::Device::NotAPushService
      subscription.destroy!
    rescue WebPush::ResponseError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Push notify failed: #{e.class}")
    end
  end
end
