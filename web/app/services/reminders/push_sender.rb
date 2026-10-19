module Reminders
  # Sends a Web Push digest to every device of the member (PRD §6). Each device gets a
  # delivery_attempts row: accepted (201, waiting for the device's receipt), rejected (404/410:
  # the subscription is deleted) or error. Any accepted → awaiting_receipt; none → failed.
  class PushSender
    TTL = 24.hours

    def self.call(delivery) = new(delivery).call

    def initialize(delivery)
      @delivery = delivery
      @user = delivery.user
    end

    def call
      subscriptions = @user.push_subscriptions.to_a
      return fail!(I18n.t("reminders.push.no_device", locale: :en)) if subscriptions.empty?

      payload = Reminders::PushPayload.for(@delivery)
      accepted = subscriptions.count { |subscription| send_to(subscription, payload) }
      if accepted.positive?
        @delivery.update!(status: "awaiting_receipt", dispatched_at: @delivery.dispatched_at || Time.current, attempts: @delivery.attempts + 1, error: nil)
      else
        fail!(@delivery.delivery_attempts.order(:id).last&.error || "rejected by every device")
      end
    end

    private

    def send_to(subscription, payload)
      token = SecureRandom.urlsafe_base64(24)
      attempt = @delivery.delivery_attempts.create!(push_subscription_id: subscription.id, channel: "web_push", status: "error",
        receipt_token_digest: Digest::SHA256.hexdigest(token), attempted_at: Time.current)
      body = payload.merge(receipt_url: Rails.application.routes.url_helpers.push_receipt_path(token)).to_json
      response = WebPush.payload_send(message: body, endpoint: subscription.endpoint, p256dh: subscription.p256dh,
        auth: subscription.auth, ttl: TTL.to_i, urgency: "high", vapid: Vapid.options)
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

    def fail!(reason)
      @delivery.update!(status: "failed", failed_at: Time.current, error: reason, owner_notified_at: nil,
        dispatched_at: @delivery.dispatched_at || Time.current, attempts: @delivery.attempts + 1)
    end
  end
end
