# Hourly (PRD §6): a push no device confirmed within 24h is failed (an asynchronous failure); the
# owner hears about it in the next daily summary.
class ConfirmPushReceiptsJob < ApplicationJob
  queue_as :default

  def perform
    ReminderDelivery.awaiting_receipt.where(dispatched_at: ...Reminders::PushSender::TTL.ago).find_each do |delivery|
      ReminderDelivery.transaction do
        delivery.delivery_attempts.accepted.each do |attempt|
          label = PushSubscription.find_by(id: attempt.push_subscription_id)&.device_label || "device"
          attempt.update!(error: "#{label}: #{I18n.t('reminders.push.no_receipt', locale: :en)}")
        end
        delivery.update!(status: "failed", failed_at: Time.current, owner_notified_at: nil,
          error: I18n.t("reminders.push.no_receipt", locale: :en))
      end
    end
  end
end
