module Spike
  class SendPushJob < ApplicationJob
    queue_as :default

    def perform(push_send)
      subscription = push_send.subscription
      payload = {
        title: "我的家 push spike",
        body: "Scheduled #{push_send.scheduled_for.in_time_zone('Asia/Taipei').strftime('%H:%M')} · sent #{Time.current.in_time_zone('Asia/Taipei').strftime('%H:%M:%S')}",
        url: "/spike/push",
        receipt_url: "/spike/push/receipts/#{push_send.receipt_token}"
      }

      response = WebPush.payload_send(
        message: payload.to_json,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        ttl: 24.hours.to_i,
        urgency: "high",
        vapid: { subject: Vapid.subject, public_key: Vapid.public_key, private_key: Vapid.private_key }
      )
      push_send.update!(sent_at: Time.current, http_status: response.code.to_i)
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
      push_send.update!(sent_at: Time.current, http_status: e.response&.code&.to_i, error: e.class.name)
      subscription.destroy!
    rescue WebPush::ResponseError => e
      push_send.update!(sent_at: Time.current, http_status: e.response&.code&.to_i, error: e.message.truncate(250))
    end
  end
end
