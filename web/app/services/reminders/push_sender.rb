module Reminders
  # Sends a Web Push digest to every device of the member (PRD §6). Each device gets a
  # delivery_attempts row: accepted (201, waiting for the device's receipt), rejected (404/410:
  # the subscription is deleted) or error. Any accepted → awaiting_receipt; none → failed.
  class PushSender
    TTL = Push::Device::TTL

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

    def send_to(subscription, payload) = Push::Device.deliver(subscription, payload, attempts: @delivery.delivery_attempts)

    def fail!(reason)
      @delivery.update!(status: "failed", failed_at: Time.current, error: reason, owner_notified_at: nil,
        dispatched_at: @delivery.dispatched_at || Time.current, attempts: @delivery.attempts + 1)
    end
  end
end
