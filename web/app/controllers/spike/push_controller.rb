module Spike
  class PushController < BaseController
    def show
      @vapid_public_key = Vapid.public_key
      @subscriptions = PushSubscription.order(created_at: :desc)
      @sends = PushSend.includes(:subscription).order(created_at: :desc).limit(50)
    end

    # POST /spike/push/subscription (JSON from the browser's PushSubscription.toJSON())
    def subscribe
      data = params.require(:subscription).permit(:endpoint, keys: [ :p256dh, :auth ])
      subscription = PushSubscription.find_or_initialize_by(endpoint: data[:endpoint])
      subscription.update!(p256dh: data.dig(:keys, :p256dh), auth: data.dig(:keys, :auth), user_agent: request.user_agent)
      head :created
    end

    # POST /spike/push/sends  (delay_minutes: 0 = now)
    def create_send
      delay = params[:delay_minutes].to_i.clamp(0, 12 * 60)
      PushSubscription.find_each do |subscription|
        push_send = subscription.sends.create!(scheduled_for: delay.minutes.from_now)
        SendPushJob.set(wait: delay.minutes).perform_later(push_send)
      end
      redirect_to spike_push_path, notice: "Queued for #{delay.zero? ? 'now' : "#{delay} min from now"}"
    end
  end
end
