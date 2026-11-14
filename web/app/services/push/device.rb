module Push
  # Sends one push to one device with a receipt token (PRD §6). The attempt is created on
  # `attempts` (a reminder digest's or a notification's delivery_attempts): accepted (201, waiting
  # for the device's receipt), rejected (404/410: the subscription is deleted) or error.
  module Device
    TTL = 24.hours

    module_function

    # true when the push service accepted it
    def deliver(subscription, payload, attempts:, urgency: "high")
      token = SecureRandom.urlsafe_base64(24)
      attempt = attempts.create!(push_subscription_id: subscription.id, channel: "web_push", status: "error",
        receipt_token_digest: Digest::SHA256.hexdigest(token), attempted_at: Time.current)
      body = payload.merge(receipt_url: Rails.application.routes.url_helpers.push_receipt_path(token)).to_json
      response = WebPush.payload_send(message: body, endpoint: subscription.endpoint, p256dh: subscription.p256dh,
        auth: subscription.auth, ttl: TTL.to_i, urgency:, vapid: Vapid.options)
      attempt.update!(status: "accepted", http_status: response.code.to_i)
      subscription.update_columns(last_success_at: Time.current)
      true
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
      attempt.update!(status: "rejected", http_status: e.response&.code&.to_i, error: "#{subscription.device_label}: subscription expired (#{e.response&.code})")
      subscription.destroy!
      false
    rescue WebPush::ResponseError => e
      attempt.update!(status: "rejected", http_status: e.response&.code&.to_i, error: "#{subscription.device_label}: #{e.message.first(200)}")
      false
    end
  end
end
