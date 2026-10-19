# A plain push without receipts, for messages that aren't digests (the owner's failure summary).
# Dead subscriptions (404/410) are removed; other errors are ignored (in-app always has a copy).
module WebPushNotifier
  module_function

  def notify(user, title:, body:, url:)
    user.push_subscriptions.find_each do |subscription|
      WebPush.payload_send(message: { title:, body:, url: }.to_json, endpoint: subscription.endpoint, p256dh: subscription.p256dh,
        auth: subscription.auth, ttl: 24.hours.to_i, urgency: "high", vapid: Vapid.options)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      subscription.destroy!
    rescue WebPush::ResponseError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Push notify failed: #{e.message}")
    end
  end
end
