module Push
  # Sends one push to one device with a receipt token (PRD §6). The attempt is created on
  # `attempts` (a reminder digest's or a notification's delivery_attempts): accepted (201, waiting
  # for the device's receipt), rejected (404/410: the subscription is deleted) or error.
  module Device
    TTL = 24.hours
    # A push service answers in well under a second; never wait long on one
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # The subscription's endpoint isn't one of the push services (PushSubscription::PUSH_HOSTS)
    NotAPushService = Class.new(StandardError)

    module_function

    # Posts one message to the subscription's push service, and to nowhere else
    def post(subscription, message, urgency:)
      raise NotAPushService unless PushSubscription.push_service?(subscription.endpoint)

      WebPush.payload_send(message:, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
        ttl: TTL.to_i, urgency:, vapid: Vapid.options, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, ssl_timeout: OPEN_TIMEOUT)
    end

    # true when the push service accepted it
    def deliver(subscription, payload, attempts:, urgency: "high")
      token = SecureRandom.urlsafe_base64(24)
      attempt = attempts.create!(push_subscription_id: subscription.id, channel: "web_push", status: "error",
        receipt_token_digest: Digest::SHA256.hexdigest(token), attempted_at: Time.current)
      body = payload.merge(receipt_url: Rails.application.routes.url_helpers.push_receipt_path(token)).to_json
      response = post(subscription, body, urgency:)
      attempt.update!(status: "accepted", http_status: response.code.to_i)
      subscription.update_columns(last_success_at: Time.current)
      true
    rescue NotAPushService
      attempt.update!(status: "rejected", error: "#{subscription.device_label}: not a push service")
      subscription.destroy!
      false
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
      attempt.update!(status: "rejected", http_status: e.response&.code&.to_i, error: "#{subscription.device_label}: subscription expired (#{e.response&.code})")
      subscription.destroy!
      false
    rescue WebPush::ResponseError => e
      # Only what kind of refusal it was: the answer's own text is the other end's to choose
      attempt.update!(status: "rejected", http_status: e.response&.code&.to_i,
        error: "#{subscription.device_label}: #{e.class.name.demodulize.titleize.downcase} (#{e.response&.code})")
      false
    end
  end
end
